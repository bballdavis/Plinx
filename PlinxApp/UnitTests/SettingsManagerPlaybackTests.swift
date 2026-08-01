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

    func test_downloadQualitySelectionPersistsForFutureEnqueues() {
        let settings = SettingsManager(userDefaults: defaults)

        settings.setDownloadQuality(.megabits3_720p)

        XCTAssertEqual(settings.downloads.quality, .megabits3_720p)
        let reloaded = SettingsManager(userDefaults: defaults)
        XCTAssertEqual(reloaded.downloads.quality, .megabits3_720p)
    }

    func test_loadingOutOfRangePersistedVolumeClampsImmediately() {
        let stored = """
        {
          "playback": {
            "autoPlayNextEpisode": true,
            "seekBackwardSeconds": 10,
            "seekForwardSeconds": 10,
            "player": "mpv",
            "subtitleScale": 100,
            "maxVolumePercent": -20
          },
          "interface": {},
          "downloads": {}
        }
        """
        defaults.set(Data(stored.utf8), forKey: "strimr.settings")

        XCTAssertEqual(SettingsManager(userDefaults: defaults).playback.maxVolumePercent, 0)
    }

    func test_disableUnsupportedExternalDiscovery_turnsOffPersistedSeerrTab() {
        let stored = """
        {
          "playback": {
            "autoPlayNextEpisode": true,
            "seekBackwardSeconds": 10,
            "seekForwardSeconds": 10,
            "maxVolumePercent": 65
          },
          "interface": {
            "displaySeerrDiscoverTab": true
          },
          "downloads": {}
        }
        """
        defaults.set(Data(stored.utf8), forKey: "strimr.settings")
        let settings = SettingsManager(userDefaults: defaults)

        XCTAssertTrue(settings.interface.displaySeerrDiscoverTab)

        PlinxSettingsSanitizer.disableUnsupportedExternalDiscovery(settings)

        XCTAssertFalse(settings.interface.displaySeerrDiscoverTab)
        let reloaded = SettingsManager(userDefaults: defaults)
        XCTAssertFalse(reloaded.interface.displaySeerrDiscoverTab)
    }

    func test_disableUnsupportedExternalDiscovery_keepsDisabledSetting() {
        let settings = SettingsManager(userDefaults: defaults)
        settings.setDisplaySeerrDiscoverTab(false)

        PlinxSettingsSanitizer.disableUnsupportedExternalDiscovery(settings)

        XCTAssertFalse(settings.interface.displaySeerrDiscoverTab)
    }

    func test_plinxDefaults_disableCollectionsWhenSettingIsMissing() {
        let settings = SettingsManager(userDefaults: defaults)

        PlinxSettingsSanitizer.applyPlinxDefaults(settings, userDefaults: defaults)

        XCTAssertFalse(settings.interface.displayCollections)
    }

    func test_plinxDefaults_preservePersistedCollectionsPreference() {
        var settings = SettingsManager(userDefaults: defaults)
        settings.setDisplayCollections(true)

        PlinxSettingsSanitizer.applyPlinxDefaults(settings, userDefaults: defaults)
        XCTAssertTrue(settings.interface.displayCollections)

        settings.setDisplayCollections(false)
        settings = SettingsManager(userDefaults: defaults)
        PlinxSettingsSanitizer.applyPlinxDefaults(settings, userDefaults: defaults)
        XCTAssertFalse(settings.interface.displayCollections)
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
        ratings: nil,
        media: nil,
        markers: nil,
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
