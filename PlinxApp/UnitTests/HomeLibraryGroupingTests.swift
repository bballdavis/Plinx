import XCTest
@testable import Plinx

final class HomeLibraryGroupingTests: XCTestCase {
    private let movieLibrary = Library(
        id: "1",
        title: "Movies",
        type: .movie,
        sectionId: 1,
        agent: "tv.plex.agents.movie"
    )
    private let showLibrary = Library(
        id: "2",
        title: "TV Shows",
        type: .show,
        sectionId: 2,
        agent: "tv.plex.agents.series"
    )
    private let clipLibrary = Library(
        id: "3",
        title: "Home Videos",
        type: .clip,
        sectionId: 3
    )
    private let youtubeLibrary = Library(
        id: "6",
        title: "YouTube Videos",
        type: .movie,
        sectionId: 6,
        agent: "tv.plex.agents.none"
    )

    func test_standardMovieAndShowLibraries_areMoviesOrTV() {
        XCTAssertTrue(HomeLibraryGrouping.isMoviesOrTV(movieLibrary))
        XCTAssertTrue(HomeLibraryGrouping.isMoviesOrTV(showLibrary))
        XCTAssertFalse(HomeLibraryGrouping.isOtherVideo(movieLibrary))
        XCTAssertFalse(HomeLibraryGrouping.isOtherVideo(showLibrary))
    }

    func test_clipAndNoneAgentLibraries_areOtherVideos() {
        XCTAssertTrue(HomeLibraryGrouping.isOtherVideo(clipLibrary))
        XCTAssertTrue(HomeLibraryGrouping.isOtherVideo(youtubeLibrary))
        XCTAssertFalse(HomeLibraryGrouping.isMoviesOrTV(clipLibrary))
        XCTAssertFalse(HomeLibraryGrouping.isMoviesOrTV(youtubeLibrary))
    }

    func test_missingLibrary_isNotInferredAsOtherVideo() {
        XCTAssertFalse(HomeLibraryGrouping.isOtherVideo(nil))
        XCTAssertFalse(HomeLibraryGrouping.isMoviesOrTV(nil))
    }

    func test_continueWatchingRows_keepMixedContentInSingleRow() {
        let hub = Hub(
            id: "continue",
            title: "Continue Watching",
            items: [
                makeDisplayItem(id: "movie-1", type: .movie),
                makeDisplayItem(id: "episode-1", type: .episode),
                makeDisplayItem(id: "clip-1", type: .clip)
            ]
        )

        let rows = HomeLibraryGrouping.continueWatchingRows(from: hub)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.sectionKey, "continueWatching")
        XCTAssertEqual(rows.first?.items.map(\.id), ["movie-1", "episode-1", "clip-1"])
    }
}

private func makeDisplayItem(id: String, type: PlexItemType) -> MediaDisplayItem {
    .playable(
        MediaItem(
            id: id,
            guid: "guid://\(id)",
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
            contentRating: nil,
            studio: nil,
            tagline: nil,
            thumbPath: "/library/metadata/\(id)/thumb",
            artPath: "/library/metadata/\(id)/art",
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
        )
    )
}
