import XCTest
@testable import Plinx

private let projectionServer = ServerIdentity(provider: .plex, id: "projection-server")

final class HomeRecentlyAddedProjectionTests: XCTestCase {
    private let movies = Library(
        id: "1",
        title: "Movies",
        type: .movie,
        sectionId: 1,
        agent: "movie",
        server: projectionServer
    )
    private let shows = Library(
        id: "2",
        title: "Shows",
        type: .series,
        sectionId: 2,
        agent: "shows",
        server: projectionServer
    )
    private let youtube = Library(
        id: "6",
        title: "YouTube",
        type: .movie,
        sectionId: 6,
        agent: "tv.plex.agents.none",
        server: projectionServer
    )

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

    private func item(_ id: String, _ type: MediaKind) -> MediaDisplayItem {
        makeProjectionItem(id, type: type, contentRating: type == .episode ? "TV-Y" : "G")
    }
}

final class LibraryRecommendationFallbackPolicyTests: XCTestCase {
    private let title = "Recently Added"

    func test_currentHubsWithContentAreNeverReplacedByDiscoveryRow() {
        let current = [
            Hub(id: "hub.movie.recentlyreleased", title: "Recently Released", items: [item("a")]),
            Hub(id: "hub.movie.genre", title: "Comedy", items: [item("b")]),
        ]

        let merged = LibraryRecommendationFallbackPolicy.mergingDiscoveryHub(
            into: current,
            candidates: [item("c"), item("d")],
            title: title
        )

        XCTAssertEqual(merged.map(\.id), current.map(\.id))
    }

    func test_emptyHubsGainDiscoveryRow() {
        let merged = LibraryRecommendationFallbackPolicy.mergingDiscoveryHub(
            into: [],
            candidates: [item("c"), item("d")],
            title: title
        )

        XCTAssertEqual(merged.map(\.id), [LibraryRecommendationFallbackPolicy.discoveryHubID])
        XCTAssertEqual(merged.first?.items.map(\.id), ["c", "d"])
    }

    func test_continueWatchingOnlyGainsDiscoveryRowWithoutDuplicates() {
        let current = [Hub(id: "hub.movie.inprogress", title: "Continue Watching", items: [item("a")])]

        let merged = LibraryRecommendationFallbackPolicy.mergingDiscoveryHub(
            into: current,
            candidates: [item("a"), item("b")],
            title: title
        )

        XCTAssertEqual(merged.map(\.id), ["hub.movie.inprogress", LibraryRecommendationFallbackPolicy.discoveryHubID])
        XCTAssertEqual(merged.last?.items.map(\.id), ["b"])
    }

    func test_noCandidatesLeavesHubsUnchanged() {
        let merged = LibraryRecommendationFallbackPolicy.mergingDiscoveryHub(
            into: [],
            candidates: [],
            title: title
        )

        XCTAssertTrue(merged.isEmpty)
    }

    /// Regression: the loader used to merge into a snapshot taken before its
    /// catalog await. When a concurrent load filled the real hubs meanwhile,
    /// the stale empty snapshot plus the discovery row replaced them.
    func test_mergeAfterConcurrentLoadKeepsLoadedHubs() {
        let staleSnapshot: [Hub] = []
        XCTAssertTrue(LibraryRecommendationFallbackPolicy.needsDiscoveryHub(staleSnapshot))

        let loadedMeanwhile = [Hub(id: "hub.movie.genre", title: "Comedy", items: [item("b")])]
        let merged = LibraryRecommendationFallbackPolicy.mergingDiscoveryHub(
            into: loadedMeanwhile,
            candidates: [item("c")],
            title: title
        )

        XCTAssertEqual(merged.map(\.id), ["hub.movie.genre"])
    }

    private func item(_ id: String) -> MediaDisplayItem {
        makeProjectionItem(id, type: .movie, contentRating: "G")
    }
}

private func makeProjectionItem(_ id: String, type: MediaKind, contentRating: String) -> MediaDisplayItem {
    .playable(MediaItem(
        id: id,
        identity: MediaIdentity(server: projectionServer, itemID: id),
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
        contentRating: contentRating,
        studio: nil,
        tagline: nil,
        thumbPath: nil,
        artPath: nil,
        artworkCornerColors: nil,
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
