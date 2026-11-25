import AetherEngine
import Foundation
import Observation

@MainActor
@Observable
final class SettingsManager {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "strimr.settings"

    private(set) var settings: AppSettings

    init(userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            settings = stored
        } else {
            settings = AppSettings()
        }
    }

    var playback: PlaybackSettings {
        settings.playback
    }

    var interface: InterfaceSettings {
        settings.interface
    }

    var downloads: DownloadSettings {
        settings.downloads
    }

    func setNextEpisodeAutoplay(_ autoplay: NextEpisodeAutoplay) {
        settings.playback.nextEpisodeAutoplay = autoplay
        persist()
    }

    func setDefaultSleepTimer(_ mode: SleepTimerMode?) {
        settings.playback.defaultSleepTimer = mode
        persist()
    }

    func setPlaybackQualityPreset(_ preset: TranscodeQualityPreset) {
        settings.playback.qualityPreset = preset
        persist()
    }

    func setVideoScaleMode(_ mode: PlayerVideoScaleMode) {
        settings.playback.videoScaleMode = mode
        persist()
    }

    func setAutoRotateVideo(_ enabled: Bool) {
        settings.playback.autoRotateVideo = enabled
        persist()
    }

    func setPictureInPicture(_ enabled: Bool) {
        settings.playback.pictureInPicture = enabled
        persist()
    }

    func setBackgroundAudio(_ enabled: Bool) {
        settings.playback.backgroundAudio = enabled
        persist()
    }

    func setAutoSkipIntros(_ enabled: Bool) {
        settings.playback.autoSkipIntros = enabled
        persist()
    }

    func setAutoSkipCredits(_ enabled: Bool) {
        settings.playback.autoSkipCredits = enabled
        persist()
    }

    func setAutoSkipCommercials(_ enabled: Bool) {
        settings.playback.autoSkipCommercials = enabled
        persist()
    }

    func setTranscodeLiveTV(_ enabled: Bool) {
        settings.playback.transcodeLiveTV = enabled
        persist()
    }

    func setTintsLiveTVGuideCategories(_ enabled: Bool) {
        settings.interface.tintsLiveTVGuideCategories = enabled
        persist()
    }

    func setLiveTVSection(_ section: String, server: ServerIdentity) {
        let key = liveTVKey(server)
        guard settings.interface.liveTVSectionByServer[key] != section else { return }
        settings.interface.liveTVSectionByServer[key] = section
        persist()
    }

    func liveTVSection(server: ServerIdentity) -> String? {
        settings.interface.liveTVSectionByServer[liveTVKey(server)]
    }

    func setLiveTVChannelSort(_ sort: LiveTVChannelSort, server: ServerIdentity) {
        let key = liveTVKey(server)
        guard settings.interface.liveTVChannelSortByServer[key] != sort else { return }
        settings.interface.liveTVChannelSortByServer[key] = sort
        persist()
    }

    func liveTVChannelSort(server: ServerIdentity) -> LiveTVChannelSort {
        settings.interface.liveTVChannelSortByServer[liveTVKey(server)] ?? .number
    }

    private func liveTVKey(_ server: ServerIdentity) -> String {
        "\(server.provider.rawValue):\(server.id)"
    }

    func setReadAhead(_ readAhead: PlaybackReadAhead) {
        settings.playback.readAhead = readAhead
        persist()
    }

    func setCenterClickAction(_ action: PlayerCenterClickAction) {
        settings.playback.centerClickAction = action
        persist()
    }

    func setLosslessAudio(_ enabled: Bool) {
        settings.playback.losslessAudio = enabled
        persist()
    }

    func setSpatialAudioLayout(_ layout: SpatialSpeakerLayout?) {
        settings.playback.spatialAudioLayout = layout
        persist()
    }

    func setNightMode(_ enabled: Bool) {
        settings.playback.nightMode = enabled
        persist()
    }

    func setDialogueBoost(_ boost: DialogueBoost) {
        settings.playback.dialogueBoost = boost
        persist()
    }

    func setRememberTrackSelections(_ enabled: Bool) {
        settings.playback.rememberTrackSelections = enabled
        persist()
    }

    func setShowChaptersOnTimeline(_ enabled: Bool) {
        settings.playback.showChaptersOnTimeline = enabled
        persist()
    }

    func setShowSkipSegmentsOnTimeline(_ enabled: Bool) {
        settings.playback.showSkipSegmentsOnTimeline = enabled
        persist()
    }

    func setShowEndsAtTime(_ enabled: Bool) {
        settings.playback.showEndsAtTime = enabled
        persist()
    }

    func setShowClock(_ enabled: Bool) {
        settings.playback.showClock = enabled
        persist()
    }

    func setShowInfoWhenPaused(_ enabled: Bool) {
        settings.playback.showInfoWhenPaused = enabled
        persist()
    }

    func setShowScrubThumbnailPreviews(_ enabled: Bool) {
        settings.playback.showScrubThumbnailPreviews = enabled
        persist()
    }

    func setGenerateMissingScrubThumbnailPreviews(_ enabled: Bool) {
        settings.playback.generateMissingScrubThumbnailPreviews = enabled
        persist()
    }

    func setStyledASSSubtitles(_ enabled: Bool) {
        settings.playback.styledASSSubtitles = enabled
        persist()
    }

    func setShowSubtitlesOnSkipBack(_ enabled: Bool) {
        settings.playback.showSubtitlesOnSkipBack = enabled
        persist()
    }

    func setAutomaticSubtitleSearch(_ enabled: Bool) {
        settings.playback.automaticSubtitleSearch = enabled
        persist()
    }

    func setSeekBackwardSeconds(_ seconds: Int) {
        settings.playback.seekBackwardSeconds = seconds
        persist()
    }

    func setSeekForwardSeconds(_ seconds: Int) {
        settings.playback.seekForwardSeconds = seconds
        persist()
    }

    func setDoubleTapToSeek(_ enabled: Bool) {
        settings.playback.doubleTapToSeek = enabled
        persist()
    }

    func setAudioDelayMilliseconds(_ milliseconds: Int) {
        settings.playback.audioDelayMilliseconds = PlaybackOffsetRange.audio.clamp(milliseconds)
        persist()
    }

    func setSubtitleFontSize(_ fontSize: Int) {
        settings.playback.subtitleFontSize = fontSize
        persist()
    }

    func setSubtitleTextColor(_ color: SubtitleTextColor) {
        settings.playback.subtitleTextColor = color
        persist()
    }

    func setSubtitleBrightness(_ brightness: SubtitleBrightness) {
        settings.playback.subtitleBrightness = brightness
        persist()
    }

    func setSubtitleFontWeight(_ weight: SubtitleFontWeight) {
        settings.playback.subtitleFontWeight = weight
        persist()
    }

    func setSubtitleBackgroundStrength(_ strength: SubtitleBackgroundStrength) {
        settings.playback.subtitleBackgroundStrength = strength
        persist()
    }

    func setSubtitleEdgeStyle(_ style: SubtitleEdgeStyle) {
        settings.playback.subtitleEdgeStyle = style
        persist()
    }

    func setSubtitleVerticalPosition(_ position: SubtitleVerticalPosition) {
        settings.playback.subtitleVerticalPosition = position
        persist()
    }

    func setSubtitleBottomMargin(_ margin: SubtitleBottomMargin) {
        settings.playback.subtitleBottomMargin = margin
        persist()
    }

    func setSubtitleSearchPreferences(_ preferences: SubtitleSearchPreferences) {
        settings.playback.subtitleSearch = preferences
        persist()
    }

    func resetSubtitleAppearance() {
        settings.playback.resetSubtitleAppearance()
        persist()
    }

    func updatePlayback(_ transform: (inout PlaybackSettings) -> Void) {
        transform(&settings.playback)
        persist()
    }

    func homeRowPreferences(for scopeID: String) -> HomeRowPreferences {
        settings.interface.homeRowsByScope[scopeID] ?? HomeRowPreferences()
    }

    func setHomeRowVisibility(_ rowID: String, visible: Bool, scopeID: String) {
        var preferences = homeRowPreferences(for: scopeID)
        preferences.setRow(rowID, visible: visible)
        settings.interface.homeRowsByScope[scopeID] = preferences
        persist()
    }

    func setHomeRowOrder(_ rowIDs: [String], scopeID: String) {
        var preferences = homeRowPreferences(for: scopeID)
        preferences.setOrder(rowIDs)
        settings.interface.homeRowsByScope[scopeID] = preferences
        persist()
    }

    func resetHomeRows(scopeID: String) {
        settings.interface.homeRowsByScope.removeValue(forKey: scopeID)
        persist()
    }

    // MARK: - Home rows (per profile)

    func homeRowPreferences(profileID: String) -> HomeRowPreferences {
        settings.interface.homeRowsByProfile[profileID] ?? HomeRowPreferences()
    }

    func setHomeRowVisibility(_ rowID: String, visible: Bool, profileID: String) {
        var preferences = homeRowPreferences(profileID: profileID)
        preferences.setRow(rowID, visible: visible)
        settings.interface.homeRowsByProfile[profileID] = preferences
        persist()
    }

    func setHomeRowOrder(_ rowIDs: [String], profileID: String) {
        var preferences = homeRowPreferences(profileID: profileID)
        preferences.setOrder(rowIDs)
        settings.interface.homeRowsByProfile[profileID] = preferences
        persist()
    }

    func setHomeRowStyle(_ style: HomeRowStyle, of row: HomeRow, profileID: String) {
        var preferences = homeRowPreferences(profileID: profileID)
        preferences.setStyle(style, of: row)
        settings.interface.homeRowsByProfile[profileID] = preferences
        persist()
    }

    func resetHomeRows(profileID: String) {
        settings.interface.homeRowsByProfile.removeValue(forKey: profileID)
        persist()
    }

    // MARK: - Libraries (per profile)

    /// The profile's own library settings or, until it has some, the family's (`InterfaceSettings.familyLibraries`).
    func libraryPreferences(profileID: String) -> LibraryPreferences {
        settings.interface.librariesByProfile[profileID] ?? settings.interface.familyLibraries ?? LibraryPreferences()
    }

    /// A profile's first change starts from the family's library settings and gives the profile its own.
    func updateLibraryPreferences(profileID: String, _ transform: (inout LibraryPreferences) -> Void) {
        var preferences = libraryPreferences(profileID: profileID)
        transform(&preferences)
        guard preferences != libraryPreferences(profileID: profileID) else { return }
        settings.interface.librariesByProfile[profileID] = storedLibraries(preferences)
        persist()
    }

    /// Forgets the libraries of `server` that a successful load for `profileID`, made with that profile's own
    /// sign-in, no longer returned. Only that profile's own settings change: a Plex Home or Jellyfin user may see only
    /// some of a server's libraries, so the libraries other profiles and the family hid must stay hidden for the
    /// profiles that see more. A profile that still uses the family's settings is left as it is.
    func pruneLibraries(of server: ServerIdentity, keeping libraryIDs: Set<String>, profileID: String) {
        guard let preferences = settings.interface.librariesByProfile[profileID] else { return }
        var pruned = preferences
        pruned.pruneLibraries(of: server, keeping: libraryIDs)
        guard pruned != preferences else { return }
        settings.interface.librariesByProfile[profileID] = storedLibraries(pruned)
        persist()
    }

    /// Moves the device-wide library list of earlier versions (`hiddenLibraryIds`, `navigationLibraryIds`) onto
    /// `servers` for every profile: it becomes the family's library settings and joins the settings profiles already
    /// have. It applies once; later calls do nothing.
    func adoptLegacyLibraries(on servers: [ServerIdentity]) {
        let interface = settings.interface
        guard !servers.isEmpty, !interface.hiddenLibraryIds.isEmpty || !interface.navigationLibraryIds.isEmpty else {
            return
        }
        let hidden = servers.flatMap { server in
            interface.hiddenLibraryIds.map { LibraryIdentity(server: server, libraryID: $0) }
        }
        let pinned = servers.flatMap { server in
            interface.navigationLibraryIds.map { LibraryIdentity(server: server, libraryID: $0) }
        }
        let adopt: (inout LibraryPreferences) -> Void = { preferences in
            for library in hidden where !preferences.isHidden(library) {
                preferences.setHidden(library, hidden: true)
            }
            for library in pinned {
                preferences.setPinned(library, pinned: true)
            }
        }
        var family = interface.familyLibraries ?? LibraryPreferences()
        adopt(&family)
        settings.interface.familyLibraries = family
        for (profileID, var preferences) in interface.librariesByProfile {
            adopt(&preferences)
            settings.interface.librariesByProfile[profileID] = preferences
        }
        settings.interface.hiddenLibraryIds = []
        settings.interface.navigationLibraryIds = []
        persist()
    }

    /// A profile's empty settings are kept while the family has some, so a profile that shows every library keeps
    /// showing them.
    private func storedLibraries(_ preferences: LibraryPreferences) -> LibraryPreferences? {
        preferences.isEmpty && settings.interface.familyLibraries == nil ? nil : preferences
    }

    // MARK: - Cleanup

    /// Removes the rows and libraries of servers whose account was removed, for every profile. Servers that are only
    /// unreachable or disabled must keep their settings.
    func removeSettings(of servers: Set<ServerIdentity>) {
        guard !servers.isEmpty else { return }
        for (profileID, preferences) in settings.interface.homeRowsByProfile {
            var cleaned = preferences
            cleaned.removeRows(of: servers)
            settings.interface.homeRowsByProfile[profileID] = cleaned.isEmpty ? nil : cleaned
        }
        if var family = settings.interface.familyLibraries {
            family.removeLibraries(of: servers)
            settings.interface.familyLibraries = family.isEmpty ? nil : family
        }
        for (profileID, preferences) in settings.interface.librariesByProfile {
            var cleaned = preferences
            cleaned.removeLibraries(of: servers)
            settings.interface.librariesByProfile[profileID] = storedLibraries(cleaned)
        }
        persist()
    }

    func removeSettings(profileID: String) {
        settings.interface.homeRowsByProfile[profileID] = nil
        settings.interface.librariesByProfile[profileID] = nil
        persist()
    }

    func updateInterface(_ transform: (inout InterfaceSettings) -> Void) {
        transform(&settings.interface)
        persist()
    }

    func libraryBrowsePreferences(for key: String) -> LibraryBrowsePreferences {
        settings.interface.libraryBrowseByKey[key] ?? LibraryBrowsePreferences()
    }

    func setLibraryBrowsePreferences(_ preferences: LibraryBrowsePreferences, for key: String) {
        guard settings.interface.libraryBrowseByKey[key] != preferences else { return }
        settings.interface.libraryBrowseByKey[key] = preferences
        persist()
    }

    var customLibraryLayoutCount: Int {
        settings.interface.libraryBrowseByKey.values.count { $0.layout != nil }
    }

    func resetLibraryLayouts() {
        for (key, preferences) in settings.interface.libraryBrowseByKey where preferences.layout != nil {
            var preferences = preferences
            preferences.layout = nil
            settings.interface.libraryBrowseByKey[key] = preferences == LibraryBrowsePreferences() ? nil : preferences
        }
        persist()
    }

    func setLibraryDefaultLayout(_ layout: LibraryDefaultLayout) {
        settings.interface.libraryDefaultLayout = layout
        persist()
    }

    func setPosterSize(_ size: PosterSize) {
        settings.interface.posterSize = size
        persist()
    }

    func setTabBarPlacement(_ placement: TabBarPlacement) {
        settings.interface.tabBarPlacement = placement
        persist()
    }

    func setStartupScreen(_ screen: StartupScreen) {
        settings.interface.startupScreen = screen
        persist()
    }

    func setThemeMusicVolume(_ volume: ThemeMusicVolume) {
        settings.interface.themeMusicVolume = volume
        persist()
    }

    func setShowsTitleLogo(_ enabled: Bool) {
        settings.interface.showsTitleLogo = enabled
        persist()
    }

    func setShowsCardLabels(_ enabled: Bool) {
        settings.interface.showsCardLabels = enabled
        persist()
    }

    func setShowsWatchStatusBadges(_ enabled: Bool) {
        settings.interface.showsWatchStatusBadges = enabled
        persist()
    }

    func setContinueWatchingAction(_ action: ContinueWatchingAction) {
        settings.interface.continueWatchingAction = action
        persist()
    }

    func setMergesNextUpIntoContinueWatching(_ enabled: Bool) {
        settings.interface.mergesNextUpIntoContinueWatching = enabled
        persist()
    }

    func setHomeHero(_ source: HomeHeroSource) {
        settings.interface.homeHero = source
        persist()
    }

    func setHomeHeroIncludesTrending(_ enabled: Bool) {
        settings.interface.homeHeroIncludesTrending = enabled
        persist()
    }

    /// Kept apart from the settings: it changes every day and holds whole items.
    func featuredSelection(profileID: String) -> FeaturedSelection? {
        defaults.data(forKey: featuredSelectionKey(profileID)).flatMap {
            try? JSONDecoder().decode(FeaturedSelection.self, from: $0)
        }
    }

    func setFeaturedSelection(_ selection: FeaturedSelection, profileID: String) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: featuredSelectionKey(profileID))
    }

    private func featuredSelectionKey(_ profileID: String) -> String {
        "strimr.home.featured.\(profileID)"
    }

    func setDisplayCollections(_ enabled: Bool) {
        settings.interface.displayCollections = enabled
        persist()
    }

    func setDisplayPlaylists(_ enabled: Bool) {
        settings.interface.displayPlaylists = enabled
        persist()
    }

    func setDisplayFavoritesTab(_ enabled: Bool) {
        settings.interface.displayFavoritesTab = enabled
        persist()
    }

    func setDisplayDownloadsTab(_ enabled: Bool) {
        settings.interface.displayDownloadsTab = enabled
        persist()
    }

    func setDisplayLiveTVTab(_ enabled: Bool) {
        settings.interface.displayLiveTVTab = enabled
        persist()
    }

    func setDisplaySeerrDiscoverTab(_ enabled: Bool) {
        settings.interface.displaySeerrDiscoverTab = enabled
        persist()
    }

    func setMultiServerSearchEnabled(_ enabled: Bool) {
        settings.interface.multiServerSearchEnabled = enabled
        persist()
    }

    func setGroupsSearchResults(_ enabled: Bool) {
        settings.interface.groupsSearchResults = enabled
        persist()
    }

    func setSpoilerProtection(_ level: SpoilerProtectionLevel) {
        settings.interface.spoilerProtection = level
        persist()
    }

    func setLandscapeEpisodeArtwork(_ artwork: LandscapeEpisodeArtwork) {
        settings.interface.landscapeEpisodeArtwork = artwork
        persist()
    }

    func setPortraitEpisodeArtwork(_ artwork: PortraitEpisodeArtwork) {
        settings.interface.portraitEpisodeArtwork = artwork
        persist()
    }

    func setDownloadWiFiOnly(_ enabled: Bool) {
        settings.downloads.wifiOnly = enabled
        persist()
    }

    func setDownloadQualityPreset(_ preset: TranscodeQualityPreset) {
        settings.downloads.qualityPreset = preset
        persist()
    }

    func setOfflineCacheLimit(megabytes: Int) {
        settings.downloads.offlineCacheLimitMB = megabytes
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: storageKey)
        } catch {
            ErrorReporter.capture(error)
        }
    }
}
