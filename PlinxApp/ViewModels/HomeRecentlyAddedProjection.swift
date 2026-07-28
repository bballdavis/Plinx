import Foundation

/// Pure projection from library-keyed catalog results into Home rows.
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

    static func rows(
        from catalogs: [LibraryCatalogResult],
        hiddenLibraryIDs: Set<String> = [],
        libraryOrder: [String] = [],
        combineMoviesTV: Bool
    ) -> [Row] {
        let visible = catalogs.filter {
            !hiddenLibraryIDs.contains($0.library.id) && !$0.items.isEmpty
        }
        let movies = visible.filter {
            HomeLibraryGrouping.isMoviesOrTV($0.library) && $0.library.type == .movie
        }
        let television = visible.filter {
            HomeLibraryGrouping.isMoviesOrTV($0.library) && $0.library.type == .show
        }
        let other = visible.filter { HomeLibraryGrouping.isOtherVideo($0.library) }

        var rows: [Row] = []
        if combineMoviesTV {
            let combined = interleave(
                deduplicated(movies.flatMap(\.items)),
                deduplicated(television.flatMap(\.items))
            )
            if !combined.isEmpty {
                let title: String
                if !movies.isEmpty && !television.isEmpty {
                    title = NSLocalizedString("home.recentlyAdded.tvAndMovies", tableName: "Plinx", comment: "")
                } else if !television.isEmpty {
                    title = NSLocalizedString("home.recentlyAdded.tv", tableName: "Plinx", comment: "")
                } else {
                    title = NSLocalizedString("home.recentlyAdded.movies", tableName: "Plinx", comment: "")
                }
                rows.append(Row(
                    id: "combined.recentlyadded.movies+shows",
                    title: title,
                    sectionKey: "moviesAndTV",
                    layout: .portrait,
                    libraryIDs: (movies + television).map(\.library.id),
                    items: combined
                ))
            }
        } else {
            let movieItems = deduplicated(movies.flatMap(\.items))
            if !movieItems.isEmpty {
                rows.append(Row(
                    id: "recentlyadded.movies",
                    title: NSLocalizedString("home.recentlyAdded.movies", tableName: "Plinx", comment: ""),
                    sectionKey: "recentMovies",
                    layout: .portrait,
                    libraryIDs: movies.map(\.library.id),
                    items: movieItems
                ))
            }

            let televisionItems = deduplicated(television.flatMap(\.items))
            if !televisionItems.isEmpty {
                rows.append(Row(
                    id: "recentlyadded.tv",
                    title: NSLocalizedString("home.recentlyAdded.tv", tableName: "Plinx", comment: ""),
                    sectionKey: "recentTV",
                    layout: .portrait,
                    libraryIDs: television.map(\.library.id),
                    items: televisionItems
                ))
            }
        }

        rows.append(contentsOf: other.map { catalog in
            Row(
                id: "recentlyadded.library.\(catalog.library.id)",
                title: catalog.library.title,
                sectionKey: "otherVideos",
                layout: .landscape,
                libraryIDs: [catalog.library.id],
                items: deduplicated(catalog.items)
            )
        })

        guard !libraryOrder.isEmpty else { return rows }
        return rows.enumerated().sorted { lhs, rhs in
            let left = orderIndex(for: lhs.element, order: libraryOrder)
            let right = orderIndex(for: rhs.element, order: libraryOrder)
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }

    private static func deduplicated(_ items: [MediaDisplayItem]) -> [MediaDisplayItem] {
        var seen: Set<String> = []
        return items.filter { seen.insert($0.id).inserted }
    }

    private static func interleave(
        _ movies: [MediaDisplayItem],
        _ television: [MediaDisplayItem]
    ) -> [MediaDisplayItem] {
        var result: [MediaDisplayItem] = []
        for index in 0..<max(movies.count, television.count) {
            if index < movies.count { result.append(movies[index]) }
            if index < television.count { result.append(television[index]) }
        }
        return deduplicated(result)
    }

    private static func orderIndex(for row: Row, order: [String]) -> Int {
        row.libraryIDs.compactMap { order.firstIndex(of: $0) }.min() ?? .max
    }
}
