import Foundation

/// Pure projection of safety-filtered recently-added hubs into the rows shown
/// by the Plinx home screen. Network loading and safety filtering stay outside
/// this type so category preservation can be tested without a live Plex server.
enum HomeRecentlyAddedProjection {
    enum Layout: Equatable {
        case portrait
        case landscape
    }

    struct Row: Identifiable, Equatable {
        let id: String
        let title: String
        let sectionKey: String
        let layout: Layout
        let libraryIDs: [String]
        let items: [MediaDisplayItem]
    }

    private enum Category: Equatable {
        case movies
        case tv
        case other
    }

    private struct Entry {
        let hub: Hub
        let library: Library?
        let category: Category
    }

    static func rows(
        from hubs: [Hub],
        libraries: [Library],
        hiddenLibraryIDs: Set<String> = [],
        libraryOrder: [String] = [],
        combineMoviesTV: Bool,
        recentlyAddedPrefix: String
    ) -> [Row] {
        let entries = hubs.compactMap { hub -> Entry? in
            let library = HomeLibraryGrouping.matchLibrary(
                for: hub,
                in: libraries,
                recentlyAddedPrefix: recentlyAddedPrefix
            )
            if let libraryID = library?.id, hiddenLibraryIDs.contains(libraryID) {
                return nil
            }

            return Entry(
                hub: hub,
                library: library,
                category: category(for: hub, library: library, recentlyAddedPrefix: recentlyAddedPrefix)
            )
        }

        let movieEntries = entries.filter { $0.category == .movies }
        let tvEntries = entries.filter { $0.category == .tv }
        let otherEntries = entries.filter { $0.category == .other }
        var rows: [Row] = []

        if combineMoviesTV {
            let movieItems = movieEntries.flatMap { $0.hub.items }
            let tvItems = tvEntries.flatMap { $0.hub.items }
            let combined = interleave(movieItems, tvItems)
            if !combined.isEmpty {
                let title: String
                let movieEnabled = libraries.contains {
                    $0.type == .movie
                        && HomeLibraryGrouping.isMoviesOrTV($0)
                        && !hiddenLibraryIDs.contains($0.id)
                }
                let tvEnabled = libraries.contains {
                    $0.type == .show
                        && HomeLibraryGrouping.isMoviesOrTV($0)
                        && !hiddenLibraryIDs.contains($0.id)
                }
                if movieEnabled && tvEnabled {
                    title = NSLocalizedString("home.recentlyAdded.tvAndMovies", tableName: "Plinx", comment: "")
                } else if !tvEntries.isEmpty {
                    title = NSLocalizedString("home.recentlyAdded.tv", tableName: "Plinx", comment: "")
                } else {
                    title = NSLocalizedString("home.recentlyAdded.movies", tableName: "Plinx", comment: "")
                }
                rows.append(Row(
                    id: "combined.recentlyadded.movies+shows",
                    title: title,
                    sectionKey: "moviesAndTV",
                    layout: .portrait,
                    libraryIDs: (movieEntries + tvEntries).compactMap { $0.library?.id },
                    items: combined
                ))
            }
        } else {
            let movieItems = movieEntries.flatMap { $0.hub.items }
            if !movieItems.isEmpty {
                rows.append(Row(
                    id: "recentlyadded.movies",
                    title: NSLocalizedString("home.recentlyAdded.movies", tableName: "Plinx", comment: ""),
                    sectionKey: "recentMovies",
                    layout: .portrait,
                    libraryIDs: movieEntries.compactMap { $0.library?.id },
                    items: movieItems
                ))
            }
            let tvItems = tvEntries.flatMap { $0.hub.items }
            if !tvItems.isEmpty {
                rows.append(Row(
                    id: "recentlyadded.tv",
                    title: NSLocalizedString("home.recentlyAdded.tv", tableName: "Plinx", comment: ""),
                    sectionKey: "recentTV",
                    layout: .portrait,
                    libraryIDs: tvEntries.compactMap { $0.library?.id },
                    items: tvItems
                ))
            }
        }

        rows.append(contentsOf: otherEntries.map { entry in
            Row(
                id: entry.hub.id,
                title: entry.hub.title,
                sectionKey: "otherVideos",
                layout: .landscape,
                libraryIDs: entry.library.map { [$0.id] } ?? [],
                items: entry.hub.items
            )
        })

        guard !libraryOrder.isEmpty else { return rows }
        return rows.enumerated().sorted { lhs, rhs in
            let leftIndex = orderIndex(for: lhs.element, order: libraryOrder)
            let rightIndex = orderIndex(for: rhs.element, order: libraryOrder)
            return leftIndex == rightIndex ? lhs.offset < rhs.offset : leftIndex < rightIndex
        }.map(\.element)
    }

    private static func category(for hub: Hub, library: Library?, recentlyAddedPrefix: String) -> Category {
        if let library {
            if HomeLibraryGrouping.isOtherVideo(library) { return .other }
            return library.type == .show ? .tv : .movies
        }
        if HomeLibraryGrouping.isLikelyOtherVideoHub(hub, recentlyAddedPrefix: recentlyAddedPrefix) {
            return .other
        }
        if hub.items.contains(where: { $0.type == .episode || $0.type == .season || $0.type == .show }) {
            return .tv
        }
        if hub.items.contains(where: { $0.type == .movie }) {
            return .movies
        }
        return .other
    }

    private static func interleave(_ movies: [MediaDisplayItem], _ tv: [MediaDisplayItem]) -> [MediaDisplayItem] {
        var result: [MediaDisplayItem] = []
        let count = max(movies.count, tv.count)
        for index in 0..<count {
            if index < movies.count { result.append(movies[index]) }
            if index < tv.count { result.append(tv[index]) }
        }
        return result
    }

    private static func orderIndex(for row: Row, order: [String]) -> Int {
        row.libraryIDs.compactMap { order.firstIndex(of: $0) }.min() ?? Int.max
    }
}
