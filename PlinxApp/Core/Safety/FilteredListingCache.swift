import Foundation

/// Pages of a filtered listing, indexed in the filtered listing.
///
/// Screens page through server listings by index and trust the reported total. Dropping blocked titles from each
/// server page would leave holes at the end of every page and a total that counts titles that never appear. This cache
/// keeps, per listing, the allowed titles gathered so far and where the server listing continues, so a page's
/// `startIndex` and the reported count always describe the filtered listing:
///
/// - A request at index 0 starts the listing over (every refresh starts there).
/// - The reported count is the number of allowed titles known so far. It never counts a title that does not exist,
///   and while the server has more, it runs at least one page past the requested one so screens keep paging.
/// - A policy change starts every listing over.
@MainActor
final class FilteredListingCache<Element> {
    struct Page {
        let items: [Element]
        let startIndex: Int
        /// Allowed titles known so far: exact once `reachedEnd`, otherwise at least one page past `items`.
        let knownCount: Int
        let reachedEnd: Bool
    }

    struct ServerPage {
        let items: [Element]
        /// Size of the unfiltered listing, when the server reports it.
        let totalCount: Int?
    }

    private struct Listing {
        var allowed: [Element] = []
        var serverCursor = 0
        var reachedEnd = false
        let policyRevision: Int
        var lastUse: UInt64
    }

    /// Server pages fetched at most per request, so a long run of blocked titles cannot turn one scroll into hundreds
    /// of requests. The listing continues from there on the next request.
    static var maximumServerPagesPerRequest: Int {
        25
    }

    static var minimumServerPageSize: Int {
        50
    }

    private let capacity: Int
    private var listings: [String: Listing] = [:]
    private var busyKeys: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var useCounter: UInt64 = 0

    init(capacity: Int = 24) {
        self.capacity = max(capacity, 1)
    }

    /// - Parameters:
    ///   - key: Identifies the listing: the same server request apart from its position.
    ///   - shown: What the listing shows of a server element; `nil` drops it.
    ///   - fetch: Loads the unfiltered server listing at a server index.
    func page(
        key: String,
        startIndex: Int,
        limit: Int,
        policyRevision: Int,
        shown: (Element) -> Element?,
        fetch: (_ serverStart: Int, _ serverLimit: Int) async throws -> ServerPage,
    ) async throws -> Page {
        await acquire(key)
        defer { release(key) }

        let start = max(startIndex, 0)
        let size = max(limit, 1)
        useCounter &+= 1
        var listing: Listing = if start > 0, let existing = listings[key], existing.policyRevision == policyRevision {
            existing
        } else {
            Listing(policyRevision: policyRevision, lastUse: useCounter)
        }
        listing.lastUse = useCounter

        let serverPageSize = max(size, Self.minimumServerPageSize)
        // The requested page plus one more, so the count shows whether another page exists.
        let target = start + size * 2
        var fetchedPages = 0
        do {
            while !listing.reachedEnd, listing.allowed.count < target,
                  fetchedPages < Self.maximumServerPagesPerRequest
            {
                try Task.checkCancellation()
                let page = try await fetch(listing.serverCursor, serverPageSize)
                fetchedPages += 1
                listing.serverCursor += page.items.count
                listing.allowed += page.items.compactMap(shown)
                if let total = page.totalCount {
                    listing.reachedEnd = page.items.isEmpty || listing.serverCursor >= total
                } else {
                    listing.reachedEnd = page.items.count < serverPageSize
                }
            }
        } catch {
            // Keep what was gathered, so a retry continues where this one stopped.
            store(listing, for: key)
            throw error
        }
        store(listing, for: key)

        let end = min(start + size, listing.allowed.count)
        let items = start < end ? Array(listing.allowed[start ..< end]) : []
        return Page(items: items, startIndex: start, knownCount: listing.allowed.count, reachedEnd: listing.reachedEnd)
    }

    func removeAll() {
        listings.removeAll()
    }

    private func store(_ listing: Listing, for key: String) {
        listings[key] = listing
        guard listings.count > capacity,
              let oldest = listings.min(by: { $0.value.lastUse < $1.value.lastUse })?.key
        else { return }
        listings.removeValue(forKey: oldest)
    }

    // MARK: - One request per listing at a time

    /// Requests for the same listing run one after the other: each continues where the previous one stopped.
    private func acquire(_ key: String) async {
        while busyKeys.contains(key) {
            await withCheckedContinuation { continuation in
                waiters[key, default: []].append(continuation)
            }
        }
        busyKeys.insert(key)
    }

    private func release(_ key: String) {
        busyKeys.remove(key)
        for waiter in waiters.removeValue(forKey: key) ?? [] {
            waiter.resume()
        }
    }
}
