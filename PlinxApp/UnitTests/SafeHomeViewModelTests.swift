import XCTest
import PlinxCore
@testable import Plinx

@MainActor
final class SafeHomeViewModelTests: XCTestCase {

    private let strictPolicy = SafetyPolicy.ratingOnly(maxMovie: .g, maxTV: .tvY, allowUnrated: false)
    private let permissivePolicy = SafetyPolicy.ratingOnly(maxMovie: .g, maxTV: .tvY, allowUnrated: true)

    func test_recentlyAdded_otherVideoHub_preservedUnderStrictPolicy() {
        let context = PlexAPIContext()
        let settings = SettingsManager()
        let libraryStore = LibraryStore(context: context)
        libraryStore.libraries = [
            Library(
                id: "6",
                title: "Youtube Videos",
                type: .movie,
                sectionId: 6,
                agent: "tv.plex.agents.none"
            )
        ]

        let inner = HomeViewModel(context: context, settingsManager: settings, libraryStore: libraryStore)
        let unratedMovieLikeItem = MediaItem.fixture(type: .movie, contentRating: nil)
        inner.recentlyAdded = [
            Hub(id: "hub.home.recentlyadded.6", title: "Recently Added Youtube Videos", items: [.playable(unratedMovieLikeItem)])
        ]

        let safe = SafeHomeViewModel(inner: inner, policy: permissivePolicy, libraryStore: libraryStore)
        safe.updatePolicy(strictPolicy)

        XCTAssertEqual(safe.recentlyAdded.count, 1, "Other-video hubs should not be dropped when strict unrated filtering is enabled")
        XCTAssertEqual(safe.recentlyAdded.first?.items.count, 1)
    }

    func test_recentlyAdded_movieHub_stillFilteredUnderStrictPolicy() {
        let context = PlexAPIContext()
        let settings = SettingsManager()
        let libraryStore = LibraryStore(context: context)
        libraryStore.libraries = [
            Library(id: "1", title: "Movies", type: .movie, sectionId: 1, agent: "tv.plex.agents.movie")
        ]

        let inner = HomeViewModel(context: context, settingsManager: settings, libraryStore: libraryStore)
        let unratedMovieItem = MediaItem.fixture(type: .movie, contentRating: nil)
        inner.recentlyAdded = [
            Hub(id: "hub.home.recentlyadded.1", title: "Recently Added Movies", items: [.playable(unratedMovieItem)])
        ]

        let safe = SafeHomeViewModel(inner: inner, policy: permissivePolicy, libraryStore: libraryStore)
        safe.updatePolicy(strictPolicy)

        XCTAssertTrue(safe.recentlyAdded.isEmpty, "Movie hubs with unrated movie items must still be filtered under strict policy")
    }
}

private extension MediaItem {
    static func fixture(
        id: String = "fixture-id",
        type: PlexItemType = .movie,
        contentRating: String? = nil
    ) -> MediaItem {
        MediaItem(
            id: id,
            guid: "plex://\(type)/\(id)",
            summary: nil,
            title: "Test Item",
            type: type,
            parentRatingKey: nil,
            grandparentRatingKey: nil,
            genres: [],
            year: nil,
            duration: nil,
            videoResolution: nil,
            rating: nil,
            contentRating: contentRating,
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
        )
    }
}
