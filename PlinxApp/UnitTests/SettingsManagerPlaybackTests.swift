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

    func test_downloadQualityPresetSelectionPersistsForFutureEnqueues() {
        let settings = SettingsManager(userDefaults: defaults)

        settings.setDownloadQualityPreset(.p720_2mbps)

        XCTAssertEqual(settings.downloads.qualityPreset, .p720_2mbps)
        let reloaded = SettingsManager(userDefaults: defaults)
        XCTAssertEqual(reloaded.downloads.qualityPreset, .p720_2mbps)
    }

    /// A parent's pre-fork download quality (stored as `downloads.quality`) survives the upgrade
    /// through the real settings store, and the next save writes it under the new key.
    func test_preForkDownloadQualitySurvivesLoadAndNextSave() {
        let stored = """
        {
          "playback": {
            "autoPlayNextEpisode": true,
            "seekBackwardSeconds": 10,
            "seekForwardSeconds": 10
          },
          "interface": {},
          "downloads": {
            "wifiOnly": true,
            "quality": "megabits3_720p"
          }
        }
        """
        defaults.set(Data(stored.utf8), forKey: "strimr.settings")

        let settings = SettingsManager(userDefaults: defaults)
        XCTAssertEqual(settings.downloads.qualityPreset, .p720_2mbps)

        settings.setDownloadWiFiOnly(false)

        let reloaded = SettingsManager(userDefaults: defaults)
        XCTAssertEqual(reloaded.downloads.qualityPreset, .p720_2mbps)
        XCTAssertFalse(reloaded.downloads.wifiOnly)
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

    // MARK: - Visible Libraries (search)

    func test_hiddenLibraries_areReadForTheirProfileOnly() {
        let settings = SettingsManager(userDefaults: defaults)
        let libraries = [
            Library(id: "1", title: "Movies", type: .movie, sectionId: 1, server: plexServer),
            Library(id: "2", title: "Shows", type: .series, sectionId: 2, server: plexServer),
            Library(id: "3", title: "Videos", type: .clip, sectionId: 3, server: plexServer),
        ]

        settings.updateLibraryPreferences(profileID: "kid") { $0.hiddenLibraries = [libraries[1].identity] }

        let hidden = PlinxLibraryVisibility.hiddenLibraries(settingsManager: settings, profileID: "kid")
        XCTAssertEqual(hidden, [LibraryIdentity(server: plexServer, libraryID: "2")])
        XCTAssertEqual(libraries.filter { !hidden.contains($0.identity) }.map(\.id), ["1", "3"])
        XCTAssertTrue(PlinxLibraryVisibility.hiddenLibraries(settingsManager: settings, profileID: "other").isEmpty)

        let reloaded = SettingsManager(userDefaults: defaults)
        XCTAssertEqual(PlinxLibraryVisibility.hiddenLibraries(settingsManager: reloaded, profileID: "kid"), hidden)
    }

    func test_searchResultFiltering_respectsHiddenLibraries() {
        let hidden: Set<LibraryIdentity> = [LibraryIdentity(server: plexServer, libraryID: "2")]
        let visibleItem = makeSearchSource(itemID: "visible", librarySectionID: "3", server: plexServer)
        let hiddenItem = makeSearchSource(itemID: "hidden", librarySectionID: "2", server: plexServer)
        let sameLibraryIDOtherServer = makeSearchSource(itemID: "other", librarySectionID: "2", server: otherServer)

        XCTAssertTrue(PlinxLibraryVisibility.isVisible(visibleItem.media, on: plexServer, hiddenLibraries: hidden))
        XCTAssertFalse(PlinxLibraryVisibility.isVisible(hiddenItem.media, on: plexServer, hiddenLibraries: hidden))
        XCTAssertEqual(
            PlinxLibraryVisibility.visibleSources(
                [visibleItem, hiddenItem, sameLibraryIDOtherServer],
                hiddenLibraries: hidden,
            ).map(\.media.id),
            ["visible", "other"],
        )
    }

    /// A result that does not name its library cannot be matched, so it is hidden while the
    /// profile hides any library of that server, and shown when the profile hides nothing there.
    func test_searchResultWithoutLibrary_failsClosedWhileItsServerHidesALibrary() {
        let hidden: Set<LibraryIdentity> = [LibraryIdentity(server: plexServer, libraryID: "2")]
        let unscopedHere = makeSearchSource(itemID: "shared", librarySectionID: nil, server: plexServer)
        let unscopedElsewhere = makeSearchSource(itemID: "jellyfin", librarySectionID: nil, server: otherServer)

        XCTAssertFalse(PlinxLibraryVisibility.isVisible(unscopedHere.media, on: plexServer, hiddenLibraries: hidden))
        XCTAssertTrue(
            PlinxLibraryVisibility.isVisible(unscopedElsewhere.media, on: otherServer, hiddenLibraries: hidden),
        )
        XCTAssertTrue(PlinxLibraryVisibility.isVisible(unscopedHere.media, on: plexServer, hiddenLibraries: []))
    }
}

private let plexServer = ServerIdentity(provider: .plex, id: "plex-server")
private let otherServer = ServerIdentity(provider: .jellyfin, id: "jellyfin-server")

private func makeSearchSource(
    itemID: String,
    librarySectionID: String?,
    server: ServerIdentity,
) -> SearchResultSource {
    let item = MediaItem(
        id: itemID,
        identity: MediaIdentity(server: server, itemID: itemID),
        guid: "plex://movie/\(itemID)",
        summary: nil,
        title: "Item \(itemID)",
        type: .movie,
        parentRatingKey: nil,
        grandparentRatingKey: nil,
        genres: [],
        year: nil,
        duration: nil,
        videoResolution: nil,
        rating: nil,
        ratings: [],
        contentRating: "G",
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
        parentThumbPath: nil,
        librarySectionID: librarySectionID,
    )
    return SearchResultSource(server: server, serverName: server.id, media: .playable(item))
}
