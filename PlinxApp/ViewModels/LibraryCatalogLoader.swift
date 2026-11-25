import Foundation

struct LibraryCatalogResult: Equatable {
    let library: Library
    let items: [MediaDisplayItem]
}

@MainActor
protocol LibraryCatalogLoading {
    func recentItems(for library: Library, limit: Int) async throws -> LibraryCatalogResult
}

/// The most recently added titles of one library, newest first.
///
/// Reads through the library's `MediaServices`, so `SafeMediaServices` has
/// already dropped every title the parent's policy blocks. The gate is asked
/// again here because these titles are shown to children as they are.
@MainActor
final class LibraryCatalogLoader: LibraryCatalogLoading {
    private let services: MediaServices
    private let gate: ContentSafetyGate

    init(services: MediaServices, gate: ContentSafetyGate = .shared) {
        self.services = services
        self.gate = gate
    }

    func recentItems(for library: Library, limit: Int) async throws -> LibraryCatalogResult {
        let candidates = try await newestItems(in: library, limit: max(limit, 1))
        var seen: Set<String> = []
        let items = candidates.filter { item in
            guard item.playableItem != nil else { return false }
            guard seen.insert(item.id).inserted else { return false }
            return gate.isAllowed(item)
        }
        return LibraryCatalogResult(library: library, items: Array(items.prefix(limit)))
    }

    private func newestItems(in library: Library, limit: Int) async throws -> [MediaDisplayItem] {
        if let advanced = services.library as? any PlexAdvancedLibraryService,
           let browsePath = library.plexBrowsePath
        {
            // Titles only: collections are not recently added media.
            var queryItems = [
                URLQueryItem(name: "sort", value: "addedAt:desc"),
                URLQueryItem(name: "includeCollections", value: "0"),
            ]
            if let type = plexTypeQuery(for: library) {
                queryItems.append(URLQueryItem(name: "type", value: type))
            }
            let page = try await advanced.advancedBrowse(
                path: browsePath,
                queryItems: queryItems,
                startIndex: 0,
                limit: limit,
            )
            return page.items.compactMap { item -> MediaDisplayItem? in
                guard case let .media(media) = item else { return nil }
                return media
            }
        }

        if let browse = services.library as? any AdvancedLibraryBrowseService {
            var query = LibraryBrowseQuery()
            query.sort = .dateAdded
            query.sortDirection = .descending
            return try await browse.browseItems(
                in: library,
                parentID: nil,
                query: query,
                startIndex: 0,
                limit: limit,
            ).items
        }

        // Providers without a sortable listing: their own order.
        return try await services.library.items(in: library, parentID: nil, startIndex: 0, limit: limit).items
    }

    /// None-agent libraries (YouTube, Home Videos) mix item types, so they are not narrowed.
    private func plexTypeQuery(for library: Library) -> String? {
        if library.isNoneAgentLibrary { return nil }
        if library.isShared { return PlexSharedLibrary.videoTypes }
        switch library.type {
        case .movie: return "1"
        case .series: return "2"
        default: return nil
        }
    }
}
