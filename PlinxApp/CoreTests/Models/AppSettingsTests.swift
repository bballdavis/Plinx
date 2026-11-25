import AetherEngine
import Foundation
@testable import Plinx
import Testing

@MainActor
struct AppSettingsTests {
    @Test func `missing library browse preferences decode as empty`() throws {
        let settings = try decode(#"{"interface":{"displayPlaylists":false}}"#)

        #expect(settings.interface.libraryBrowseByKey.isEmpty)
        #expect(!settings.interface.displayPlaylists)
    }

    @Test func `theme music is off unless chosen`() throws {
        #expect(try decode(#"{"interface":{}}"#).interface.themeMusicVolume == .off)
        #expect(try decode(#"{"interface":{"themeMusicVolume":"loud"}}"#).interface.themeMusicVolume == .off)
        #expect(try decode(#"{"interface":{"themeMusicVolume":"medium"}}"#).interface.themeMusicVolume == .medium)
    }

    @Test func `episode artwork keeps the episode image and series poster unless chosen`() throws {
        let defaults = try decode(#"{"interface":{}}"#).interface
        #expect(defaults.landscapeEpisodeArtwork == .episode)
        #expect(defaults.portraitEpisodeArtwork == .series)

        let unknown = try decode(#"{"interface":{"landscapeEpisodeArtwork":"x","portraitEpisodeArtwork":"x"}}"#)
        #expect(unknown.interface.landscapeEpisodeArtwork == .episode)
        #expect(unknown.interface.portraitEpisodeArtwork == .series)

        let chosen =
            try decode(#"{"interface":{"landscapeEpisodeArtwork":"series","portraitEpisodeArtwork":"season"}}"#)
        #expect(chosen.interface.landscapeEpisodeArtwork == .series)
        #expect(chosen.interface.portraitEpisodeArtwork == .season)
    }

    @Test func `subtitle search follows the device language until chosen`() throws {
        #expect(try decode(#"{"playback":{}}"#).playback.subtitleSearch == SubtitleSearchPreferences())

        var settings = AppSettings()
        settings.playback.subtitleSearch = SubtitleSearchPreferences(language: "fr", hearingImpaired: true)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.playback.subtitleSearch == settings.playback.subtitleSearch)
    }

    @Test func `title logo is shown unless turned off`() throws {
        #expect(try decode(#"{"interface":{"displayPlaylists":false}}"#).interface.showsTitleLogo)
        #expect(try !decode(#"{"interface":{"showsTitleLogo":false}}"#).interface.showsTitleLogo)
    }

    @Test func `card labels are shown unless turned off`() throws {
        #expect(try decode(#"{"interface":{"displayPlaylists":false}}"#).interface.showsCardLabels)
        #expect(try !decode(#"{"interface":{"showsCardLabels":false}}"#).interface.showsCardLabels)
    }

    @Test func `watch status badges are shown unless turned off`() throws {
        #expect(try decode(#"{"interface":{}}"#).interface.showsWatchStatusBadges)
        #expect(try !decode(#"{"interface":{"showsWatchStatusBadges":false}}"#).interface.showsWatchStatusBadges)
    }

    @Test func `continue watching opens details unless chosen`() throws {
        #expect(try decode(#"{"interface":{}}"#).interface.continueWatchingAction == .openDetails)
        #expect(try decode(#"{"interface":{"continueWatchingAction":"x"}}"#).interface
            .continueWatchingAction == .openDetails)
        #expect(try decode(#"{"interface":{"continueWatchingAction":"play"}}"#).interface
            .continueWatchingAction == .play)
    }

    /// Plinx has no playback speed setting: videos always play at normal speed. A speed saved by an earlier build is
    /// ignored, the playback settings beside it still load, and the next save drops it.
    @Test func `a saved default playback speed is ignored and dropped on the next save`() throws {
        let decoded = try decode(#"{"playback":{"defaultPlaybackRate":1.5,"maxVolumePercent":40}}"#)
        #expect(decoded.playback.maxVolumePercent == 40)

        let encoded = try String(decoding: JSONEncoder().encode(decoded), as: UTF8.self)
        #expect(!encoded.contains("defaultPlaybackRate"))
    }

    @Test func `tab bar stays on top unless chosen`() throws {
        #expect(try decode(#"{"interface":{}}"#).interface.tabBarPlacement == .top)
        #expect(try decode(#"{"interface":{"tabBarPlacement":"x"}}"#).interface.tabBarPlacement == .top)
        #expect(try decode(#"{"interface":{"tabBarPlacement":"sidebar"}}"#).interface.tabBarPlacement == .sidebar)
    }

    @Test func `app opens on Home unless another screen is chosen`() throws {
        #expect(try decode(#"{"interface":{}}"#).interface.startupScreen == .home)
        #expect(try decode(#"{"interface":{"startupScreen":"x"}}"#).interface.startupScreen == .home)
        #expect(try decode(#"{"interface":{"startupScreen":"liveTV"}}"#).interface.startupScreen == .liveTV)
    }

    @Test func `corrupt library browse preferences keep other settings`() throws {
        let settings = try decode(#"""
        {"interface":{"displayPlaylists":false,"libraryBrowseByKey":{"plex|server|account|1":{"plex":{"filters":42}}}}}
        """#)

        #expect(settings.interface.libraryBrowseByKey.isEmpty)
        #expect(!settings.interface.displayPlaylists)
    }

    @Test func `library browse preferences survive a round trip`() throws {
        var query = LibraryBrowseQuery()
        query.sort = .dateAdded
        query.sortDirection = .descending
        query.watchStatus = .unplayed
        query.isFavorite = true
        query.genreIDs = ["genre"]
        query.years = [1999, 2024]
        let preferences = LibraryBrowsePreferences(
            plex: .init(
                displayTypeKey: "/library/sections/1/all?type=1",
                sortKey: "addedAt",
                sortDirection: .desc,
                sortQueryValue: "addedAt:desc",
                filters: ["genre": .init(isEnabled: true, optionKey: "28", optionFastKey: nil, optionTitle: "Action")],
            ),
            jellyfinQuery: query,
        )
        var settings = AppSettings()
        settings.interface.libraryBrowseByKey["key"] = preferences

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded.interface.libraryBrowseByKey["key"] == preferences)
    }

    @MainActor
    @Test func `saved library browse preferences survive a reload`() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        var preferences = LibraryBrowsePreferences()
        preferences.plex = .init(sortKey: "addedAt", sortDirection: .desc, sortQueryValue: "addedAt:desc")

        SettingsManager(userDefaults: defaults).setLibraryBrowsePreferences(preferences, for: "key")
        let reloaded = SettingsManager(userDefaults: defaults)

        #expect(reloaded.libraryBrowsePreferences(for: "key") == preferences)
    }

    @MainActor
    @Test func `the live TV channel sort is saved per server`() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        let plex = ServerIdentity(provider: .plex, id: "server")
        let jellyfin = ServerIdentity(provider: .jellyfin, id: "server")

        SettingsManager(userDefaults: defaults).setLiveTVChannelSort(.name, server: plex)
        let reloaded = SettingsManager(userDefaults: defaults)

        #expect(reloaded.liveTVChannelSort(server: plex) == .name)
        #expect(reloaded.liveTVChannelSort(server: jellyfin) == .number)
    }

    @Test func `missing pause screen setting decodes as enabled`() throws {
        let settings = try decode(#"{"playback":{"showClock":true}}"#)

        #expect(settings.playback.showInfoWhenPaused)
        #expect(settings.playback.showClock)
    }

    @Test func `missing library display defaults decode as automatic and medium`() throws {
        let settings = try decode(#"{"interface":{"libraryDefaultLayout":"mosaic"}}"#)

        #expect(settings.interface.libraryDefaultLayout == .automatic)
        #expect(settings.interface.posterSize == .medium)
    }

    @MainActor
    @Test func `resetting library layouts keeps sort and filters`() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        let manager = SettingsManager(userDefaults: defaults)
        var withSelection = LibraryBrowsePreferences(layout: .list)
        withSelection.plex = .init(sortKey: "addedAt")
        manager.setLibraryBrowsePreferences(withSelection, for: "a")
        manager.setLibraryBrowsePreferences(LibraryBrowsePreferences(layout: .grid), for: "b")
        #expect(manager.customLibraryLayoutCount == 2)

        manager.resetLibraryLayouts()

        #expect(manager.customLibraryLayoutCount == 0)
        #expect(manager.libraryBrowsePreferences(for: "a").plex?.sortKey == "addedAt")
        #expect(manager.interface.libraryBrowseByKey["b"] == nil)
    }

    @Test func `skip segments are hidden on the timeline unless turned on`() throws {
        #expect(try !decode(#"{"playback":{"showClock":true}}"#).playback.showSkipSegmentsOnTimeline)
        #expect(try decode(#"{"playback":{"showSkipSegmentsOnTimeline":true}}"#).playback.showSkipSegmentsOnTimeline)
    }

    @Test func `missing audio delay decodes as zero`() throws {
        let settings = try decode(#"{"playback":{"losslessAudio":true}}"#)

        #expect(settings.playback.audioDelayMilliseconds == 0)
        #expect(settings.playback.losslessAudio)
    }

    @Test func `read-ahead defaults to standard and survives an unknown value`() throws {
        #expect(try decode(#"{"playback":{}}"#).playback.readAhead == .standard)
        #expect(try decode(#"{"playback":{"readAhead":"maximum"}}"#).playback.readAhead == .maximum)

        let settings = try decode(#"{"playback":{"readAhead":"huge","seekForwardSeconds":30}}"#)
        #expect(settings.playback.readAhead == .standard)
        #expect(settings.playback.seekForwardSeconds == 30)
    }

    @Test func `standard read-ahead keeps the engine default window`() {
        #expect(PlaybackReadAhead.standard.forwardBufferSegments == nil)
        #expect(PlaybackReadAhead.extended.forwardBufferSegments == 75)
        #expect(PlaybackReadAhead.maximum.forwardBufferSegments == .max)
        #expect(PlaybackReadAhead.standard.softwarePacketCacheStorage == .automatic)
        #expect(PlaybackReadAhead.maximum.softwarePacketCacheStorage == .disk)
    }

    @Test func `out of range audio delay decodes clamped`() throws {
        #expect(try decode(#"{"playback":{"audioDelayMilliseconds":9000}}"#).playback.audioDelayMilliseconds == 2000)
        #expect(try decode(#"{"playback":{"audioDelayMilliseconds":-9000}}"#).playback.audioDelayMilliseconds == -2000)
    }

    @Test func `corrupt audio delay keeps other settings`() throws {
        let settings = try decode(#"{"playback":{"audioDelayMilliseconds":"late","seekForwardSeconds":30}}"#)

        #expect(settings.playback.audioDelayMilliseconds == 0)
        #expect(settings.playback.seekForwardSeconds == 30)
    }

    @Test func `audio enhancements are off unless chosen`() throws {
        let playback = try decode(#"{"playback":{"dialogueBoost":"loud","seekForwardSeconds":30}}"#).playback

        #expect(!playback.nightMode)
        #expect(playback.dialogueBoost == .off)
        #expect(playback.seekForwardSeconds == 30)
        #expect(!playback.audioShaping.isActive)
    }

    @Test func `audio enhancements combine into one shaping`() throws {
        let playback = try decode(#"{"playback":{"nightMode":true,"dialogueBoost":"strong"}}"#).playback

        #expect(playback.audioShaping.compressor == .night)
        #expect(playback.audioShaping.dialogueGainDB == 8)
        #expect(playback.audioShaping.maxChannels == nil)
    }

    /// Plinx keeps both off until a parent turns them on (docs/security/privacy-and-safety.md).
    @Test func `picture in picture and background audio stay off unless turned on`() throws {
        let defaults = try decode(#"{"playback":{}}"#).playback
        #expect(!defaults.pictureInPicture)
        #expect(!defaults.backgroundAudio)
        #expect(!AppSettings().playback.pictureInPicture)
        #expect(!AppSettings().playback.backgroundAudio)

        let enabled = try decode(#"{"playback":{"pictureInPicture":true,"backgroundAudio":true}}"#).playback
        #expect(enabled.pictureInPicture)
        #expect(enabled.backgroundAudio)

        let invalid = try decode(#"{"playback":{"pictureInPicture":"x","backgroundAudio":1}}"#).playback
        #expect(!invalid.pictureInPicture)
        #expect(!invalid.backgroundAudio)
    }

    @Test func `subtitle brightness is full unless chosen`() throws {
        #expect(try decode(#"{"playback":{}}"#).playback.subtitleBrightness == .full)
        #expect(try decode(#"{"playback":{"subtitleBrightness":"medium"}}"#).playback.subtitleBrightness == .medium)
    }

    @Test func `unknown subtitle brightness keeps other subtitle settings`() throws {
        let settings = try decode(#"{"playback":{"subtitleBrightness":"dim","subtitleTextColor":"cream"}}"#)

        #expect(settings.playback.subtitleBrightness == .full)
        #expect(settings.playback.subtitleTextColor == .cream)
    }

    @Test func `subtitle bottom margin is automatic unless chosen`() throws {
        #expect(try decode(#"{"playback":{}}"#).playback.subtitleBottomMargin == .automatic)
        #expect(try decode(#"{"playback":{"subtitleBottomMargin":"percent8"}}"#).playback
            .subtitleBottomMargin == .percent8)
    }

    @Test func `unknown subtitle bottom margin keeps other subtitle settings`() throws {
        let settings = try decode(#"{"playback":{"subtitleBottomMargin":"huge","subtitleTextColor":"cream"}}"#)

        #expect(settings.playback.subtitleBottomMargin == .automatic)
        #expect(settings.playback.subtitleTextColor == .cream)
    }

    @Test func `resetting subtitle appearance restores the automatic bottom margin`() {
        var playback = PlaybackSettings()
        playback.subtitleBottomMargin = .percent15

        playback.resetSubtitleAppearance()

        #expect(playback.subtitleBottomMargin == .automatic)
    }

    @Test func `resetting subtitle appearance restores full brightness`() {
        var playback = PlaybackSettings()
        playback.subtitleBrightness = .low
        playback.subtitleTextColor = .lightGray

        playback.resetSubtitleAppearance()

        #expect(playback.subtitleBrightness == .full)
        #expect(playback.subtitleTextColor == .white)
    }

    @MainActor
    @Test func `saved audio delay survives a reload`() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }

        SettingsManager(userDefaults: defaults).setAudioDelayMilliseconds(-350)

        #expect(SettingsManager(userDefaults: defaults).playback.audioDelayMilliseconds == -350)
    }

    /// Upstream builds saved an external player choice. Plinx never hands playback to another app and does not read
    /// it, but the rest of the saved settings, the parent's volume cap included, still load.
    @Test func `settings saved with an upstream external player still load`() throws {
        let settings = try decode(Self.upstreamExternalPlayerSettings)

        #expect(settings.playback.showClock)
        #expect(settings.playback.maxVolumePercent == 40)
    }

    @Test func `a corrupt upstream external player keeps other settings`() throws {
        let settings = try decode(#"{"playback":{"externalPlayer":{"known":{"_0":"mpv"}},"showClock":true}}"#)

        #expect(settings.playback.showClock)
    }

    @MainActor
    @Test func `the next save drops an upstream external player`() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set(Data(Self.upstreamExternalPlayerSettings.utf8), forKey: "strimr.settings")

        let manager = SettingsManager(userDefaults: defaults)
        #expect(manager.playback.maxVolumePercent == 40)
        manager.setAudioDelayMilliseconds(0)

        let data = try #require(defaults.data(forKey: "strimr.settings"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let playback = try #require(object["playback"] as? [String: Any])
        #expect(playback["externalPlayer"] == nil)
        #expect(playback["customExternalPlayer"] == nil)
        #expect(playback["maxVolumePercent"] as? Int == 40)
    }

    private static let upstreamExternalPlayerSettings = """
    {"playback":{"externalPlayer":{"custom":{}},\
    "customExternalPlayer":{"name":"Mine","template":"mine://play?url={url}"},\
    "showClock":true,"maxVolumePercent":40}}
    """

    @Test func `commercial auto skip is off unless chosen`() throws {
        #expect(try !decode(#"{"playback":{"autoSkipIntros":true}}"#).playback.autoSkipCommercials)
        #expect(try decode(#"{"playback":{"autoSkipCommercials":true}}"#).playback.autoSkipCommercials)
    }

    @Test func `double tap to seek is on unless turned off`() throws {
        #expect(try decode(#"{"playback":{"autoSkipIntros":true}}"#).playback.doubleTapToSeek)
        #expect(try !decode(#"{"playback":{"doubleTapToSeek":false}}"#).playback.doubleTapToSeek)
    }

    @Test func `subtitles on skip back are on unless turned off`() throws {
        #expect(try decode(#"{"playback":{"autoSkipIntros":true}}"#).playback.showSubtitlesOnSkipBack)
        #expect(try !decode(#"{"playback":{"showSubtitlesOnSkipBack":false}}"#).playback.showSubtitlesOnSkipBack)
    }

    @Test func `automatic subtitle search stays off unless turned on`() throws {
        #expect(try !decode(#"{"playback":{"autoSkipIntros":true}}"#).playback.automaticSubtitleSearch)
        #expect(try decode(#"{"playback":{"automaticSubtitleSearch":true}}"#).playback.automaticSubtitleSearch)
    }

    /// Plinx has one tvOS player chrome, so the upstream player style setting is gone. A style saved by an earlier
    /// build is ignored, the playback settings beside it still load, and the next save drops it.
    @Test func `a saved player style is ignored and dropped on the next save`() throws {
        let decoded = try decode(
            #"{"playback":{"playerControlsStyle":"system","centerClickAction":"showControls","maxVolumePercent":40}}"#,
        )
        #expect(decoded.playback.centerClickAction == .showControls)
        #expect(decoded.playback.maxVolumePercent == 40)

        let encoded = try String(decoding: JSONEncoder().encode(decoded), as: UTF8.self)
        #expect(!encoded.contains("playerControlsStyle"))
    }

    @Test func `center click plays and pauses unless changed`() throws {
        #expect(try decode(#"{"playback":{}}"#).playback.centerClickAction == .playPause)
        #expect(try decode(#"{"playback":{"centerClickAction":"x"}}"#).playback.centerClickAction == .playPause)

        var settings = AppSettings()
        settings.playback.centerClickAction = .showControls
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.playback.centerClickAction == .showControls)
    }

    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }
}
