import XCTest
@testable import Plinx

final class ArtworkSelectionPolicyTests: XCTestCase {
    func test_otherVideosHomeSectionUsesThumbArtworkInLandscape() {
        let item = makeDisplayItem(id: "clip-1", type: .movie)

        let kind = ArtworkSelectionPolicy.artworkKind(
            forHomeSection: "otherVideos",
            item: item,
            isLandscape: true
        )

        XCTAssertEqual(kind, .thumb)
    }

    func test_clipAlwaysUsesThumbArtworkInLandscapeHomeRows() {
        let item = makeDisplayItem(id: "clip-1", type: .clip)

        let kind = ArtworkSelectionPolicy.artworkKind(
            forHomeSection: "continueWatching",
            item: item,
            isLandscape: true
        )

        XCTAssertEqual(kind, .thumb)
    }

    func test_regularMovieRowsKeepArtArtworkInLandscape() {
        let item = makeDisplayItem(id: "movie-1", type: .movie)

        let kind = ArtworkSelectionPolicy.artworkKind(
            forHomeSection: "moviesAndTV",
            item: item,
            isLandscape: true
        )

        XCTAssertEqual(kind, .art)
    }

    func test_noneAgentLibrariesPreferThumbArtworkForLandscapeCards() {
        let library = Library(
            id: "6",
            title: "Youtube Videos",
            type: .movie,
            sectionId: 6,
            agent: "tv.plex.agents.none"
        )

        let kind = ArtworkSelectionPolicy.preferredLandscapeArtworkKind(for: library)

        XCTAssertEqual(kind, .thumb)
    }

    func test_regularMovieLibrariesKeepArtArtworkForLandscapeCards() {
        let library = Library(
            id: "1",
            title: "Movies",
            type: .movie,
            sectionId: 1,
            agent: "tv.plex.agents.movie"
        )

        let kind = ArtworkSelectionPolicy.preferredLandscapeArtworkKind(for: library)

        XCTAssertNil(kind)
    }

    func test_continueWatchingClipsUsesThumbArtworkInLandscape() {
        let item = makeDisplayItem(id: "clip-1", type: .clip)

        let kind = ArtworkSelectionPolicy.artworkKind(
            forHomeSection: "continueWatching.otherVideos",
            item: item,
            isLandscape: true
        )

        XCTAssertEqual(kind, .thumb)
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
}