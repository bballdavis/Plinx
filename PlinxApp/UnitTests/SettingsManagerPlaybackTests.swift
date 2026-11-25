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

    // MARK: - Leaving the app

    /// Kid safety: until a parent allows playback outside the app, leaving the app closes the player.
    func test_leavingTheAppClosesThePlayerUntilAParentAllowsPlaybackOutsideIt() {
        let settings = SettingsManager(userDefaults: defaults)
        PlinxSettingsSanitizer.applyPlinxDefaults(settings, userDefaults: defaults)
        PlinxSettingsSanitizer.disableUnsupportedFeatures(settings)

        XCTAssertFalse(settings.playback.pictureInPicture)
        XCTAssertFalse(settings.playback.backgroundAudio)
        XCTAssertTrue(PlayerBackgroundPolicy.closesPlayerOnBackground(settings.playback))
    }

    /// Closing the player ends Picture in Picture and background audio, so the player stays open when a parent
    /// allows either one, and closes again once both are off.
    func test_parentAllowingPictureInPictureOrBackgroundAudioKeepsThePlayerOpen() {
        let settings = SettingsManager(userDefaults: defaults)

        settings.setPictureInPicture(true)
        XCTAssertFalse(PlayerBackgroundPolicy.closesPlayerOnBackground(settings.playback))

        settings.setPictureInPicture(false)
        settings.setBackgroundAudio(true)
        XCTAssertFalse(PlayerBackgroundPolicy.closesPlayerOnBackground(settings.playback))

        settings.setPictureInPicture(true)
        XCTAssertFalse(PlayerBackgroundPolicy.closesPlayerOnBackground(settings.playback))

        settings.setPictureInPicture(false)
        settings.setBackgroundAudio(false)
        XCTAssertTrue(PlayerBackgroundPolicy.closesPlayerOnBackground(settings.playback))
    }

    /// Picture in Picture and background audio need the audio background mode; without it iOS suspends the app
    /// and both stop, whatever the parent chose.
    func test_appDeclaresTheAudioBackgroundModeForParentAllowedPlayback() {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]

        XCTAssertEqual(modes, ["audio"])
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

    /// Plinx plays only in its own tvOS player chrome; the upstream system player style no longer exists. A style
    /// saved by an earlier build must not cost a parent their volume ceiling, and the next save drops it.
    func test_savedSystemPlayerStyleKeepsTheParentVolumeCeilingAndIsDroppedOnSave() throws {
        let stored = """
        {
          "playback": {
            "autoPlayNextEpisode": true,
            "seekBackwardSeconds": 10,
            "seekForwardSeconds": 10,
            "playerControlsStyle": "system",
            "maxVolumePercent": 35
          },
          "interface": {},
          "downloads": {}
        }
        """
        defaults.set(Data(stored.utf8), forKey: "strimr.settings")

        let settings = SettingsManager(userDefaults: defaults)
        XCTAssertEqual(settings.playback.maxVolumePercent, 35)

        settings.setDownloadWiFiOnly(false)

        let saved = try XCTUnwrap(defaults.data(forKey: "strimr.settings"))
        XCTAssertFalse(String(decoding: saved, as: UTF8.self).contains("playerControlsStyle"))
        XCTAssertEqual(SettingsManager(userDefaults: defaults).playback.maxVolumePercent, 35)
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

    /// Earlier versions hid libraries for the whole device. After the update every profile, including a
    /// Plex Home user that appears later, keeps them hidden until a parent changes that profile.
    func test_librariesHiddenBeforeProfiles_stayHiddenForEveryProfile() {
        let settings = SettingsManager(userDefaults: defaults)
        settings.updateInterface { $0.hiddenLibraryIds = ["2"] }
        let hiddenShows = LibraryIdentity(server: plexServer, libraryID: "2")

        settings.adoptLegacyLibraries(on: [plexServer])

        for profileID in ["plex.parent", "plex.kid", "plex.sibling-added-later"] {
            XCTAssertEqual(
                PlinxLibraryVisibility.hiddenLibraries(settingsManager: settings, profileID: profileID),
                [hiddenShows],
            )
        }
        let reloaded = SettingsManager(userDefaults: defaults)
        XCTAssertEqual(
            PlinxLibraryVisibility.hiddenLibraries(settingsManager: reloaded, profileID: "plex.kid"),
            [hiddenShows],
        )

        // A parent showing the library for one profile changes only that profile.
        reloaded.updateLibraryPreferences(profileID: "plex.parent") { $0.setHidden(hiddenShows, hidden: false) }
        XCTAssertTrue(
            PlinxLibraryVisibility.hiddenLibraries(settingsManager: reloaded, profileID: "plex.parent").isEmpty,
        )
        XCTAssertEqual(
            PlinxLibraryVisibility.hiddenLibraries(settingsManager: reloaded, profileID: "plex.kid"),
            [hiddenShows],
        )
    }

    /// Each profile lists a server's libraries with its own sign-in, and a restricted Plex Home user sees only
    /// the libraries shared with them. Loading that user's libraries must not unhide a library for an older
    /// sibling who can see it.
    func test_libraryLoadForOneProfile_keepsTheLibrariesOtherProfilesHid() {
        let settings = SettingsManager(userDefaults: defaults)
        let movies = LibraryIdentity(server: plexServer, libraryID: "1")
        let teen = LibraryIdentity(server: plexServer, libraryID: "5")
        let deleted = LibraryIdentity(server: plexServer, libraryID: "9")
        let otherServerLibrary = LibraryIdentity(server: otherServer, libraryID: "9")
        settings.updateLibraryPreferences(profileID: "plex.older-kid") { $0.hiddenLibraries = [teen] }
        settings.updateLibraryPreferences(profileID: "plex.younger-kid") {
            $0.hiddenLibraries = [movies, deleted, otherServerLibrary]
        }

        // The younger kid's token lists only library 1: library 5 is not shared with them and 9 was deleted.
        settings.pruneLibraries(of: plexServer, keeping: ["1"], profileID: "plex.younger-kid")

        XCTAssertEqual(
            PlinxLibraryVisibility.hiddenLibraries(settingsManager: settings, profileID: "plex.older-kid"),
            [teen],
        )
        XCTAssertEqual(
            PlinxLibraryVisibility.hiddenLibraries(settingsManager: settings, profileID: "plex.younger-kid"),
            [movies, otherServerLibrary],
        )
        let reloaded = SettingsManager(userDefaults: defaults)
        XCTAssertEqual(
            PlinxLibraryVisibility.hiddenLibraries(settingsManager: reloaded, profileID: "plex.older-kid"),
            [teen],
        )
    }

    /// Libraries hidden before the update stay hidden for every profile that still uses the family's settings,
    /// whatever a restricted profile's load lists.
    func test_libraryLoadForOneProfile_keepsTheFamilyLibraries() {
        let settings = SettingsManager(userDefaults: defaults)
        settings.updateInterface { $0.hiddenLibraryIds = ["5"] }
        settings.adoptLegacyLibraries(on: [plexServer])
        let teen = LibraryIdentity(server: plexServer, libraryID: "5")

        settings.pruneLibraries(of: plexServer, keeping: ["1"], profileID: "plex.younger-kid")

        for profileID in ["plex.younger-kid", "plex.older-kid"] {
            XCTAssertEqual(
                PlinxLibraryVisibility.hiddenLibraries(settingsManager: settings, profileID: profileID),
                [teen],
            )
        }
        XCTAssertTrue(settings.interface.librariesByProfile.isEmpty)
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
