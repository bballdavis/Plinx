import Foundation
import PlinxCore

struct LibraryCatalogResult: Equatable {
    let library: Library
    let items: [MediaDisplayItem]
}

@MainActor
protocol LibraryCatalogLoading {
    func recentItems(
        for library: Library,
        limit: Int,
        policy: SafetyPolicy
    ) async throws -> LibraryCatalogResult
}

@MainActor
final class LibraryCatalogLoader: LibraryCatalogLoading {
    private let context: PlexAPIContext

    init(context: PlexAPIContext) {
        self.context = context
    }

    func recentItems(
        for library: Library,
        limit: Int,
        policy: SafetyPolicy
    ) async throws -> LibraryCatalogResult {
        guard let sectionID = library.sectionId else {
            return LibraryCatalogResult(library: library, items: [])
        }

        let repository = try SectionRepository(context: context)
        let response = try await repository.getSectionsItems(
            sectionId: sectionID,
            params: SectionRepository.SectionItemsParams(
                sort: "addedAt:desc",
                limit: limit,
                includeMeta: false,
                includeCollections: false,
                type: itemTypeQuery(for: library)
            ),
            pagination: PlexPagination(start: 0, size: limit)
        )

        var seen: Set<String> = []
        let items = (response.mediaContainer.metadata ?? [])
            .compactMap(MediaDisplayItem.init(plexItem:))
            .filter { item in
                guard item.type != .collection else { return false }
                guard seen.insert(item.id).inserted else { return false }
                return PlinxContentAuthorization.isAllowed(item, policy: policy)
            }

        return LibraryCatalogResult(library: library, items: items)
    }

    private func itemTypeQuery(for library: Library) -> String? {
        if library.isNoneAgentLibrary { return nil }
        switch library.type {
        case .movie: return "1"
        case .show: return "2"
        default: return nil
        }
    }
}

enum PlinxContentAuthorization {
    static func isAllowed(_ item: MediaItem, policy: SafetyPolicy) -> Bool {
        StrimrAdapter.isAllowed(item, policy: policy)
    }

    static func isAllowed(_ item: MediaDisplayItem, policy: SafetyPolicy) -> Bool {
        StrimrAdapter.isAllowed(item, policy: policy)
    }

    static func isAllowed(_ item: PlayableMediaItem, policy: SafetyPolicy) -> Bool {
        StrimrAdapter.isAllowed(item, policy: policy)
    }

    static func isAllowed(_ item: PlexItem, policy: SafetyPolicy) -> Bool {
        StrimrAdapter.isAllowed(item, policy: policy)
    }

    static func filtered(_ hub: Hub, policy: SafetyPolicy) -> Hub? {
        StrimrAdapter.filtered(hub, policy: policy)
    }

    static func filteredItems(
        _ items: [MediaDisplayItem],
        policy: SafetyPolicy
    ) -> [MediaDisplayItem] {
        StrimrAdapter.filteredItems(items, policy: policy)
    }
}
