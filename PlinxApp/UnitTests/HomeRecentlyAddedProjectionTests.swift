import XCTest
@testable import Plinx

final class HomeRecentlyAddedProjectionTests: XCTestCase {
    private let movies = Library(id: "1", title: "Movies", type: .movie, sectionId: 1, agent: "movie")
    private let shows = Library(id: "2", title: "Shows", type: .show, sectionId: 2, agent: "shows")
    private let youtube = Library(id: "6", title: "YouTube", type: .movie, sectionId: 6, agent: "tv.plex.agents.none")

    func test_combinedProjection_keepsYouTubeSeparateAndLandscape() {
        let rows = HomeRecentlyAddedProjection.rows(
            from: [
                result(movies, [item("movie", .movie)]),
                result(shows, [item("episode", .episode)]),
                result(youtube, [item("youtube", .movie)])
            ],
            combineMoviesTV: true
        )

        XCTAssertEqual(rows.map(\.sectionKey), ["moviesAndTV", "otherVideos"])
        XCTAssertEqual(rows[0].items.map(\.id), ["movie", "episode"])
        XCTAssertEqual(rows[1].items.map(\.id), ["youtube"])
        XCTAssertEqual(rows[1].layout, .landscape)
    }

    func test_splitProjection_preservesThreeCategories() {
        let rows = HomeRecentlyAddedProjection.rows(
            from: [
                result(movies, [item("movie", .movie)]),
                result(shows, [item("episode", .episode)]),
                result(youtube, [item("youtube", .movie)])
            ],
            combineMoviesTV: false
        )

        XCTAssertEqual(rows.map(\.sectionKey), ["recentMovies", "recentTV", "otherVideos"])
    }

    func test_visibilityOrderingAndDeduplication() {
        let rows = HomeRecentlyAddedProjection.rows(
            from: [
                result(movies, [item("duplicate", .movie), item("duplicate", .movie)]),
                result(youtube, [item("youtube", .movie)])
            ],
            hiddenLibraryIDs: [movies.id],
            libraryOrder: [youtube.id, movies.id],
            combineMoviesTV: false
        )

        XCTAssertEqual(rows.map(\.sectionKey), ["otherVideos"])
        XCTAssertEqual(rows.first?.items.map(\.id), ["youtube"])
    }

    func test_duplicateMovieAndTVItemsAppearOnlyOnceInCombinedRow() {
        let rows = HomeRecentlyAddedProjection.rows(
            from: [
                result(movies, [item("shared", .movie)]),
                result(shows, [item("shared", .episode)])
            ],
            combineMoviesTV: true
        )

        XCTAssertEqual(rows.first?.items.map(\.id), ["shared"])
    }

    private func result(_ library: Library, _ items: [MediaDisplayItem]) -> LibraryCatalogResult {
        LibraryCatalogResult(library: library, items: items)
    }

    private func item(_ id: String, _ type: PlexItemType) -> MediaDisplayItem {
        .playable(MediaItem(
            id: id,
            guid: "plex://\(id)",
            summary: nil,
            title: id,
            type: type,
            parentRatingKey: nil,
            grandparentRatingKey: nil,
            genres: [],
            year: nil,
            duration: nil,
            videoResolution: nil,
            rating: nil,
            ratings: [],
            contentRating: type == .episode ? "TV-Y" : "G",
            studio: nil,
            tagline: nil,
            thumbPath: nil,
            artPath: nil,
            ultraBlurColors: nil,
            viewOffset: nil,
            viewCount: nil,
            childCount: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            grandparentTitle: nil,
            parentTitle: nil,
            parentIndex: nil,
            index: nil,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil
        ))
    }
}
