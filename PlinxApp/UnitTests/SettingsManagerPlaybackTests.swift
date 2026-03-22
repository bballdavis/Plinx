import XCTest
@testable import Plinx

@MainActor
final class SettingsManagerPlaybackTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsManagerPlaybackTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_maxVolumeDefaultsToSeventyPercent() {
        let settings = SettingsManager(userDefaults: defaults)

        XCTAssertEqual(settings.playback.maxVolumePercent, 70)
    }

    func test_missingStoredMaxVolumeDefaultsToSeventyPercent() {
        let stored = """
        {
          "playback": {
            "autoPlayNextEpisode": true,
            "seekBackwardSeconds": 10,
            "seekForwardSeconds": 10,
            "player": "mpv",
            "subtitleScale": 100
          },
          "interface": {},
          "downloads": {}
        }
        """
        defaults.set(Data(stored.utf8), forKey: "strimr.settings")

        let settings = SettingsManager(userDefaults: defaults)

        XCTAssertEqual(settings.playback.maxVolumePercent, 70)
    }

    func test_setMaxVolumeClampsAndPersists() {
        let settings = SettingsManager(userDefaults: defaults)

        settings.setMaxVolumePercent(130)

        XCTAssertEqual(settings.playback.maxVolumePercent, 100)

        let reloaded = SettingsManager(userDefaults: defaults)
        XCTAssertEqual(reloaded.playback.maxVolumePercent, 100)
    }

    func test_searchVisibleSectionIDs_omitHiddenLibraries() {
        let libraries = [
            Library(id: "1", title: "Movies", type: .movie, sectionId: 1),
            Library(id: "2", title: "Shows", type: .show, sectionId: 2),
            Library(id: "3", title: "Videos", type: .clip, sectionId: 3)
        ]

        let visibleSectionIDs = SearchViewModel.resolvedVisibleSectionIDs(
            libraries: libraries,
            hiddenLibraryIDs: ["2"]
        )

        XCTAssertEqual(visibleSectionIDs, Set([1, 3]))
    }

    func test_searchResultFiltering_respectsVisibleSections() {
        let visibleSectionIDs: Set<Int> = [1, 3]
        let visibleItem = makePlexSearchItem(ratingKey: "visible", librarySectionID: 3)
        let hiddenItem = makePlexSearchItem(ratingKey: "hidden", librarySectionID: 2)

        XCTAssertTrue(SearchViewModel.shouldIncludeSearchResult(visibleItem, visibleSectionIDs: visibleSectionIDs))
        XCTAssertFalse(SearchViewModel.shouldIncludeSearchResult(hiddenItem, visibleSectionIDs: visibleSectionIDs))
    }
}

private func makePlexSearchItem(ratingKey: String, librarySectionID: Int?) -> PlexItem {
    PlexItem(
        ratingKey: ratingKey,
        key: "/library/metadata/\(ratingKey)",
        guid: "plex://movie/\(ratingKey)",
        librarySectionID: librarySectionID,
        type: .movie,
        title: "Item \(ratingKey)",
        summary: nil,
        thumb: nil,
        art: nil,
        year: nil,
        viewOffset: nil,
        lastViewedAt: nil,
        viewCount: nil,
        originallyAvailableAt: nil,
        duration: nil,
        audienceRating: nil,
        audienceRatingImage: nil,
        contentRating: nil,
        contentRatingAge: nil,
        tagline: nil,
        ultraBlurColors: nil,
        images: nil,
        guids: nil,
        genres: nil,
        countries: nil,
        directors: nil,
        writers: nil,
        roles: nil,
        media: nil,
        markers: nil,
        ratings: nil,
        slug: nil,
        studio: nil,
        rating: nil,
        chapterSource: nil,
        primaryExtraKey: nil,
        ratingImage: nil,
        index: nil,
        leafCount: nil,
        viewedLeafCount: nil,
        childCount: nil,
        parentRatingKey: nil,
        parentGuid: nil,
        parentSlug: nil,
        parentStudio: nil,
        parentKey: nil,
        parentTitle: nil,
        parentThumb: nil,
        parentYear: nil,
        parentIndex: nil,
        grandparentRatingKey: nil,
        grandparentGuid: nil,
        grandparentSlug: nil,
        titleSort: nil,
        grandparentKey: nil,
        grandparentTitle: nil,
        originalTitle: nil,
        grandparentThumb: nil,
        grandparentArt: nil,
        onDeck: nil,
        playQueueItemID: nil,
        subtype: nil,
        minYear: nil,
        maxYear: nil,
        composite: nil,
        playlistType: nil,
        smart: nil
    )
}
