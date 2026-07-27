import XCTest
import PlinxCore
@testable import Plinx

@MainActor
final class HomeRecentlyAddedProjectionTests: XCTestCase {
    private let prefix = "Recently Added"
    private let movieLibrary = Library(id: "1", title: "Movies", type: .movie, sectionId: 1, agent: "tv.plex.agents.movie")
    private let showLibrary = Library(id: "2", title: "TV Shows", type: .show, sectionId: 2, agent: "tv.plex.agents.tvshows")
    private let youtubeLibrary = Library(id: "6", title: "Youtube Videos", type: .movie, sectionId: 6, agent: "tv.plex.agents.none")

    func test_combinedRows_preserveAllMovieTVAndYouTubeItems() {
        let rows = HomeRecentlyAddedProjection.rows(
            from: [
                Hub(id: "hub.home.recentlyadded.1", title: "Recently Added Movies", items: [
                    makeDisplayItem(id: "movie-1", type: .movie, rating: "G"),
                    makeDisplayItem(id: "movie-2", type: .movie, rating: "PG")
                ]),
                Hub(id: "hub.home.recentlyadded.2", title: "Recently Added TV Shows", items: [
                    makeDisplayItem(id: "episode-1", type: .episode, rating: "TV-Y"),
                    makeDisplayItem(id: "episode-2", type: .episode, rating: "TV-PG")
                ]),
                Hub(id: "hub.home.recentlyadded.6", title: "Recently Added Youtube Videos", items: [
                    makeDisplayItem(id: "youtube-1", type: .movie, rating: "G"),
                    makeDisplayItem(id: "youtube-2", type: .movie, rating: "PG")
                ])
            ],
            libraries: [movieLibrary, showLibrary, youtubeLibrary],
            combineMoviesTV: true,
            recentlyAddedPrefix: prefix
        )

        XCTAssertEqual(rows.map(\.sectionKey), ["moviesAndTV", "otherVideos"])
        XCTAssertEqual(rows[0].items.map(\.id), ["movie-1", "episode-1", "movie-2", "episode-2"])
        XCTAssertEqual(rows[1].items.map(\.id), ["youtube-1", "youtube-2"])
        XCTAssertEqual(rows[1].layout, .landscape)
    }

    func test_splitRows_keepMoviesTVAndOtherVideosAsSeparateRows() {
        let rows = HomeRecentlyAddedProjection.rows(
            from: [
                Hub(id: "hub.home.recentlyadded.1", title: "Recently Added Movies", items: [
                    makeDisplayItem(id: "movie-1", type: .movie, rating: "G")
                ]),
                Hub(id: "hub.home.recentlyadded.2", title: "Recently Added TV Shows", items: [
                    makeDisplayItem(id: "episode-1", type: .episode, rating: "TV-Y")
                ]),
                Hub(id: "hub.home.recentlyadded.6", title: "Recently Added Youtube Videos", items: [
                    makeDisplayItem(id: "youtube-1", type: .movie, rating: "G")
                ])
            ],
            libraries: [movieLibrary, showLibrary, youtubeLibrary],
            combineMoviesTV: false,
            recentlyAddedPrefix: prefix
        )

        XCTAssertEqual(rows.map(\.sectionKey), ["recentMovies", "recentTV", "otherVideos"])
        XCTAssertEqual(rows.flatMap { $0.items.map(\.id) }, ["movie-1", "episode-1", "youtube-1"])
    }

    func test_unmatchedHubs_useSafeItemTypeFallbackInsteadOfBeingDropped() {
        let rows = HomeRecentlyAddedProjection.rows(
            from: [
                Hub(id: "hub.unknown.movie", title: "Recently Added", items: [
                    makeDisplayItem(id: "movie-1", type: .movie, rating: "G")
                ]),
                Hub(id: "hub.unknown.tv", title: "Recently Added", items: [
                    makeDisplayItem(id: "episode-1", type: .episode, rating: "TV-Y")
                ]),
                Hub(id: "hub.unknown.clip", title: "Recently Added Clips", items: [
                    makeDisplayItem(id: "clip-1", type: .clip, rating: "G")
                ])
            ],
            libraries: [],
            combineMoviesTV: false,
            recentlyAddedPrefix: prefix
        )

        XCTAssertEqual(rows.map(\.sectionKey), ["recentMovies", "recentTV", "otherVideos"])
        XCTAssertEqual(rows.flatMap { $0.items.map(\.id) }, ["movie-1", "episode-1", "clip-1"])
    }

    func test_libraryOrder_reordersOtherVideoRowsUsingMatchedLibraryID() {
        let rows = HomeRecentlyAddedProjection.rows(
            from: [
                Hub(id: "hub.home.recentlyadded.1", title: "Recently Added Movies", items: [
                    makeDisplayItem(id: "movie-1", type: .movie, rating: "G")
                ]),
                Hub(id: "hub.home.recentlyadded.6", title: "Recently Added Youtube Videos", items: [
                    makeDisplayItem(id: "youtube-1", type: .movie, rating: "G")
                ])
            ],
            libraries: [movieLibrary, youtubeLibrary],
            libraryOrder: [youtubeLibrary.id, movieLibrary.id],
            combineMoviesTV: false,
            recentlyAddedPrefix: prefix
        )

        XCTAssertEqual(rows.map(\.sectionKey), ["otherVideos", "recentMovies"])
        XCTAssertEqual(rows.first?.libraryIDs, [youtubeLibrary.id])
    }

    func test_ratedYouTube_survivesSafetyFilteringAndProjectsAsLandscapeOtherVideos() {
        let strictRows = projectedYouTubeRows(
            ratings: ["TV-Y", "TV-PG", nil],
            policy: .ratingOnly(maxMovie: .g, maxTV: .tvY, allowUnrated: false)
        )

        XCTAssertEqual(strictRows.map(\.sectionKey), ["otherVideos"])
        XCTAssertEqual(strictRows.first?.items.map(\.id), ["youtube-TV-Y"])
        XCTAssertEqual(strictRows.first?.layout, .landscape)

        let raisedRows = projectedYouTubeRows(
            ratings: ["TV-Y", "TV-PG", nil],
            policy: .ratingOnly(maxMovie: .g, maxTV: .tvPg, allowUnrated: false)
        )
        XCTAssertEqual(
            raisedRows.first?.items.map(\.id),
            ["youtube-TV-Y", "youtube-TV-PG"],
            "Raising the TV ceiling should reveal the newly eligible YouTube item without allowing unrated media"
        )

        let unratedRows = projectedYouTubeRows(
            ratings: ["TV-Y", "TV-PG", nil],
            policy: .ratingOnly(maxMovie: .g, maxTV: .tvPg, allowUnrated: true)
        )
        XCTAssertEqual(
            unratedRows.first?.items.map(\.id),
            ["youtube-TV-Y", "youtube-TV-PG", "youtube-unrated"]
        )
    }

    func test_hiddenYouTubeLibrary_removesOtherVideosRow() {
        let rows = HomeRecentlyAddedProjection.rows(
            from: [
                Hub(id: "hub.home.recentlyadded.6", title: "Recently Added Youtube Videos", items: [
                    makeDisplayItem(id: "youtube-1", type: .movie, rating: "TV-Y")
                ])
            ],
            libraries: [youtubeLibrary],
            hiddenLibraryIDs: [youtubeLibrary.id],
            combineMoviesTV: true,
            recentlyAddedPrefix: prefix
        )

        XCTAssertTrue(rows.isEmpty)
    }

    private func projectedYouTubeRows(
        ratings: [String?],
        policy: SafetyPolicy
    ) -> [HomeRecentlyAddedProjection.Row] {
        let context = PlexAPIContext()
        let settings = SettingsManager()
        let libraryStore = LibraryStore(context: context)
        libraryStore.libraries = [youtubeLibrary]

        let inner = HomeViewModel(
            context: context,
            settingsManager: settings,
            libraryStore: libraryStore
        )
        inner.recentlyAdded = [
            Hub(
                id: "hub.home.recentlyadded.6",
                title: "Recently Added Youtube Videos",
                items: ratings.map { rating in
                    makeDisplayItem(
                        id: rating.map { "youtube-\($0)" } ?? "youtube-unrated",
                        type: .movie,
                        rating: rating
                    )
                }
            )
        ]

        let safe = SafeHomeViewModel(
            inner: inner,
            policy: .ratingOnly(maxMovie: .g, maxTV: .tvY, allowUnrated: true),
            libraryStore: libraryStore
        )
        safe.updatePolicy(policy)

        return HomeRecentlyAddedProjection.rows(
            from: safe.recentlyAdded,
            libraries: libraryStore.libraries,
            combineMoviesTV: true,
            recentlyAddedPrefix: prefix
        )
    }
}

final class RecentlyAddedHubClassifierTests: XCTestCase {
    func test_recognizesDocumentedIdentifierVariants() {
        let identifiers = [
            "hub.home.recentlyadded.1",
            "home.recent.2",
            "clips.recent.3",
            "videos-recent-6"
        ]

        for identifier in identifiers {
            XCTAssertTrue(
                RecentlyAddedHubClassifier.isRecentlyAdded(identifier: identifier),
                "Expected recently-added identifier: \(identifier)"
            )
        }
    }

    func test_rejectsUnrelatedHubIdentifier() {
        XCTAssertFalse(RecentlyAddedHubClassifier.isRecentlyAdded(identifier: "hub.home.recommended.1"))
    }
}

private func makeDisplayItem(id: String, type: PlexItemType, rating: String?) -> MediaDisplayItem {
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
            contentRating: rating,
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
