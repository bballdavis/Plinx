import Foundation
import Observation
import PlinxCore

// ─────────────────────────────────────────────────────────────────────────────
// ContentSafetyGate — the one content decision every provider goes through
// ─────────────────────────────────────────────────────────────────────────────
//
// `SafeMediaServices` asks this gate about every item a provider returns, on
// Plex and Jellyfin, iOS and tvOS. The app keeps `policy` in sync with the
// parent's settings and `isParentUnlocked` in sync with
// `ParentalAccessCoordinator`.
//
// Decisions (unchanged from the Plinx decorators this replaces):
//   • A title is judged on its own `contentRating` (Plex `contentRating`,
//     Jellyfin `OfficialRating`), parsed by PlinxCore's
//     `ContentRatingNormalizer` and checked with `SafetyInterceptor`.
//   • Missing or unrecognized rating → rejected unless `policy.allowUnrated`.
//     Adult-only ratings (NC-17, X, 18) → always rejected.
//   • The rating's own scale picks the ceiling: TV ratings against the TV
//     ceiling, movie ratings against the movie ceiling, whatever the item kind.
//   • Collections and playlists are containers: they are listed, and their
//     entries are filtered one by one when opened.
//   • Server items carry no Plinx labels, so label policies see none (a policy
//     that requires a label rejects everything, which fails closed).
//
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class ContentSafetyGate {
    static let shared = ContentSafetyGate()

    /// Starts at the strictest default (G, TV-Y, no unrated content) until the app applies the parent's settings.
    var policy: SafetyPolicy {
        didSet {
            guard policy != oldValue else { return }
            interceptor = SafetyInterceptor(policy: policy)
            revision += 1
        }
    }

    /// Parent-only abilities (server management, playlist edits, subtitle downloads) work only while this is true.
    var isParentUnlocked: Bool

    /// Bumped whenever `policy` changes, so screens and caches built under the old policy reload.
    private(set) var revision = 0

    @ObservationIgnored private var interceptor: SafetyInterceptor

    init(policy: SafetyPolicy = .ratingOnly(), isParentUnlocked: Bool = false) {
        self.policy = policy
        self.isParentUnlocked = isParentUnlocked
        interceptor = SafetyInterceptor(policy: policy)
    }

    func isAllowed(_ item: MediaItem) -> Bool {
        interceptor.isAllowed(Self.plinxItem(item))
    }

    func isAllowed(_ item: MediaDisplayItem) -> Bool {
        switch item {
        case let .playable(media):
            isAllowed(media)
        case .collection, .playlist:
            true
        }
    }

    /// Why an item is allowed or rejected, for parent-facing diagnostics. Never shown to children.
    func decision(for item: MediaItem) -> FilterDecision {
        interceptor.explain(Self.plinxItem(item))
    }

    static func plinxItem(_ item: MediaItem) -> PlinxMediaItem {
        PlinxMediaItem(id: item.id, title: item.title, labels: [], contentRating: item.contentRating)
    }
}

/// Why `SafeMediaServices` refused a request.
enum ContentSafetyError: LocalizedError, Equatable {
    /// The title is above the parent's ceiling, unrated, or adult-only.
    case blocked
    /// A parent-only action while the parental gate is locked.
    case parentApprovalRequired
    /// A feature Plinx does not offer (Live TV, external players).
    case unavailable

    var errorDescription: String? {
        switch self {
        case .blocked, .unavailable:
            String(localized: "safety.content.unavailable", defaultValue: "This isn't available.")
        case .parentApprovalRequired:
            String(localized: "safety.parentApprovalRequired", defaultValue: "Ask a grown-up to unlock this.")
        }
    }
}

// MARK: - Filtering

extension ContentSafetyGate {
    func filter(_ items: [MediaItem]) -> [MediaItem] {
        items.filter(isAllowed)
    }

    func filter(_ items: [MediaDisplayItem]) -> [MediaDisplayItem] {
        items.filter(isAllowed)
    }

    /// Throws `ContentSafetyError.blocked` for a title the policy rejects.
    func requireAllowed(_ item: MediaItem) throws -> MediaItem {
        guard isAllowed(item) else { throw ContentSafetyError.blocked }
        return item
    }

    /// The hub with only allowed items; `nil` when filtering emptied it. A hub the server sent empty stays as it was.
    func filter(_ hub: Hub) -> Hub? {
        guard hub.hasItems else { return hub }
        let allowed = filter(hub.items)
        guard !allowed.isEmpty else { return nil }
        guard allowed.count != hub.items.count else { return hub }
        return Hub(
            id: hub.id,
            key: hub.key,
            hubKey: hub.hubKey,
            title: hub.title,
            size: allowed.count,
            more: hub.more,
            items: allowed,
            server: hub.server,
        )
    }

    func filter(_ hubs: [Hub]) -> [Hub] {
        hubs.compactMap(filter)
    }

    /// The row with only allowed items and copies; `nil` when filtering emptied it, unless `keepsEmptiedRows`.
    func filter(_ row: HomeRow, keepsEmptiedRows: Bool = false) -> HomeRow? {
        let hub: Hub
        if let filtered = filter(row.hub) {
            hub = filtered
        } else if keepsEmptiedRows {
            hub = Hub(
                id: row.hub.id,
                key: row.hub.key,
                hubKey: row.hub.hubKey,
                title: row.hub.title,
                size: 0,
                more: row.hub.more,
                items: [],
                server: row.hub.server,
            )
        } else {
            return nil
        }
        let shownIDs = Set(hub.items.compactMap(\.playableItem).map(\.identity))
        var copies: [MediaIdentity: [MediaItem]] = [:]
        for (identity, items) in row.copies where shownIDs.contains(identity) {
            let allowed = filter(items)
            if !allowed.isEmpty {
                copies[identity] = allowed
            }
        }
        return HomeRow(
            id: row.id,
            kind: row.kind,
            style: row.style,
            hub: hub,
            serverName: row.serverName,
            libraryName: row.libraryName,
            isExcludedFromServerHome: row.isExcludedFromServerHome,
            copies: copies,
        )
    }

    func filter(_ rows: [HomeRow], keepsEmptiedRows: Bool = false) -> [HomeRow] {
        rows.compactMap { filter($0, keepsEmptiedRows: keepsEmptiedRows) }
    }

    func filter(_ content: HomeContent) -> HomeContent {
        HomeContent(rows: filter(content.rows))
    }

    func filter(_ candidates: [FeaturedCandidate]) -> [FeaturedCandidate] {
        candidates.filter { isAllowed($0.item) }
    }

    func filter(_ entries: [PlaylistEntry]) -> [PlaylistEntry] {
        entries.filter { isAllowed($0.media) }
    }

    /// Folders are containers: their titles are filtered when the folder is opened.
    func isAllowed(_ item: LibraryBrowseItem) -> Bool {
        switch item {
        case let .media(media):
            isAllowed(media)
        case .folder:
            true
        }
    }

    func filter(_ items: [LibraryBrowseItem]) -> [LibraryBrowseItem] {
        items.filter(isAllowed)
    }

    /// Detail of an allowed title: throws when the title itself is blocked, and drops every blocked title it links to.
    func filter(_ content: MediaDetailContent) throws -> MediaDetailContent {
        _ = try requireAllowed(content.media)
        return MediaDetailContent(
            media: content.media,
            parentSeries: content.parentSeries.flatMap { isAllowed($0) ? $0 : nil },
            onDeck: content.onDeck.flatMap { isAllowed($0) ? $0 : nil },
            seasons: filter(content.seasons),
            episodes: filter(content.episodes),
            cast: content.cast,
            relatedHubs: filter(content.relatedHubs),
        )
    }

    /// The queue without blocked titles. Throws when the title it starts with is blocked.
    func filter(_ queue: PlaybackQueue) throws -> PlaybackQueue {
        guard queue.items.indices.contains(queue.currentIndex) else {
            guard queue.items.allSatisfy({ isAllowed($0.media) }) else { throw ContentSafetyError.blocked }
            return queue
        }
        let current = queue.items[queue.currentIndex]
        _ = try requireAllowed(current.media)
        var filtered = queue
        filtered.items = queue.items.filter { isAllowed($0.media) }
        filtered.currentIndex = filtered.items.firstIndex { $0.id == current.id } ?? 0
        return filtered
    }
}
