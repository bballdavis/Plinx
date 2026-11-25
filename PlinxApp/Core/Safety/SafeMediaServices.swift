import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// SafeMediaServices — the single content-safety boundary
// ─────────────────────────────────────────────────────────────────────────────
//
// `MediaServices.init` passes every provider service through this type, so
// every `MediaServices` that exists — Plex or Jellyfin, iOS or tvOS, built by
// `ServerRegistry`'s provider factories or by the demo — hands out only the
// wrapped services. There is no way to build an unfiltered one.
//
//   • Content (home, library, search, detail, favorites, playlist entries,
//     playback queues, downloads) goes through `ContentSafetyGate`: blocked
//     titles are dropped, emptied hubs and rows disappear, paged listings are
//     re-indexed so counts stay consistent, and looking up a blocked title
//     throws `ContentSafetyError.blocked`. Seasons and episodes are judged
//     against their series too: the wrappers let the gate look the series up
//     through the provider's own, unfiltered `mediaItem(id:)` first.
//   • Collections and playlists are listed without the artwork and counts the
//     server builds from all of their entries.
//   • Server rights and management are denied unless a parent has the gate
//     unlocked; playlist edits, the watchlist and subtitle downloads likewise.
//   • Live TV is off. No provider protocol hands a title to another app, so
//     there is no external-player path to disable.
//   • Artwork is passed through: it only draws paths the caller already has,
//     and the boundary hands out no path that draws a blocked title (container
//     composites are removed above).
//
// When a provider protocol gains a requirement, `SafeMediaServicesTests` fails
// until it is added to `reviewedRequirements` below with its treatment, and,
// for content, until the test probes it.
//
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
struct SafeMediaServices {
    let home: any MediaHomeService
    let library: any MediaLibraryService
    let search: any MediaSearchService
    let artwork: any MediaArtworkService
    let detail: any MediaDetailService
    let favorites: any MediaFavoritesService
    let playlists: any MediaPlaylistService
    let playback: any MediaPlaybackService
    let liveTV: any MediaLiveTVService
    let downloads: any MediaDownloadService
    let authorization: any MediaAuthorizationService
    let management: any MediaManagementService

    init(
        gate: ContentSafetyGate,
        home: any MediaHomeService,
        library: any MediaLibraryService,
        search: any MediaSearchService,
        artwork: any MediaArtworkService,
        detail: any MediaDetailService,
        favorites: any MediaFavoritesService,
        playlists: any MediaPlaylistService,
        playback: any MediaPlaybackService,
        liveTV _: any MediaLiveTVService,
        downloads: any MediaDownloadService,
        authorization: any MediaAuthorizationService,
        management: any MediaManagementService,
    ) {
        // The provider's own lookup, unfiltered: the gate needs a series' rating to judge its seasons and episodes,
        // even when the series itself is blocked.
        let lookUpSeries: ContentSafetyGate.SeriesLookup = { [detail] seriesID in
            try await detail.mediaItem(id: seriesID)
        }
        self.home = SafeHomeService(base: home, gate: gate, lookUpSeries: lookUpSeries)
        // The same choice as `OfflineServiceDecorators`, so callers casting to the browse protocols still find them.
        self.library = if let plex = library as? any MediaLibraryService & PlexAdvancedLibraryService {
            SafePlexLibraryService(base: plex, gate: gate, artwork: artwork, lookUpSeries: lookUpSeries)
        } else if let browse = library as? any MediaLibraryService & AdvancedLibraryBrowseService {
            SafeBrowseLibraryService(base: browse, gate: gate, artwork: artwork, lookUpSeries: lookUpSeries)
        } else {
            SafeLibraryService(base: library, gate: gate, artwork: artwork, lookUpSeries: lookUpSeries)
        }
        self.search = SafeSearchService(base: search, gate: gate, lookUpSeries: lookUpSeries)
        self.artwork = artwork
        self.detail = SafeDetailService(base: detail, gate: gate)
        self.favorites = SafeFavoritesService(base: favorites, gate: gate, lookUpSeries: lookUpSeries)
        self.playlists = SafePlaylistService(base: playlists, gate: gate, lookUpSeries: lookUpSeries)
        self.playback = if let memory = playback as? any MediaPlaybackService & MediaTrackSelectionMemoryService {
            SafeTrackMemoryPlaybackService(base: memory, gate: gate, lookUpSeries: lookUpSeries)
        } else {
            SafePlaybackService(base: playback, gate: gate, lookUpSeries: lookUpSeries)
        }
        liveTV = DisabledLiveTVService()
        self.downloads = SafeDownloadService(base: downloads, gate: gate, lookUpSeries: lookUpSeries)
        self.authorization = SafeAuthorizationService(base: authorization, gate: gate)
        self.management = SafeManagementService(base: management, gate: gate)
    }
}

// MARK: - Reviewed protocol requirements

extension SafeMediaServices {
    enum Treatment: String, Sendable {
        /// Returns titles: every one passes `ContentSafetyGate`, and a blocked subject throws.
        case filtered
        /// Returns collections or playlists, listed without their server artwork and counts; their entries are filtered
        /// when opened.
        case container
        /// Parent-only: refused, empty or false unless `ContentSafetyGate.isParentUnlocked`.
        case gated
        /// Returns no titles (writes, reports, settings, artwork of paths the caller already has).
        case passthrough
        /// Never reaches the provider (Live TV, unfiltered letter counts).
        case disabled
    }

    /// Every requirement of the protocols `MediaServices` is built from or stores, and of the offline caches its
    /// wrappers expose, by protocol and selector, with how the boundary treats it. `SafeMediaServicesTests` parses the
    /// protocol declarations and `MediaServices`' stored services, and fails when this list and the protocols differ.
    static let reviewedRequirements: [String: [String: Treatment]] = [
        "MediaHomeService": [
            "loadHome(hiddenLibraryIDs:includesPlaylists:shownRowIDs:mergesNextUp:)": .filtered,
            "loadWatchingRows(hiddenLibraryIDs:mergesNextUp:)": .filtered,
            "homeRowCatalog(hiddenLibraryIDs:)": .filtered,
            "loadFeaturedCandidates(hiddenLibraryIDs:)": .filtered,
            "items(in:startIndex:limit:)": .filtered,
            "supportsContinueWatchingRemoval": .passthrough,
            "removeFromContinueWatching(itemID:)": .passthrough,
        ],
        "MediaLibraryService": [
            "libraries()": .passthrough,
            "preview(for:)": .filtered,
            "recommended(in:mergesNextUp:)": .filtered,
            "items(in:parentID:startIndex:limit:)": .filtered,
            "collections(in:)": .container,
            "playlists(in:)": .container,
        ],
        "PlexAdvancedLibraryService": [
            "advancedBrowse(path:queryItems:startIndex:limit:)": .filtered,
            "filterOptions(path:queryItems:)": .passthrough,
            "sectionCharacters(path:queryItems:)": .disabled,
            "collectionCharacters(sectionID:)": .disabled,
            "collectionPage(sectionID:startIndex:limit:)": .filtered,
        ],
        "AdvancedLibraryBrowseService": [
            "browseItems(in:parentID:query:startIndex:limit:)": .filtered,
            "browseFilterOptions(in:)": .passthrough,
        ],
        "MediaSearchService": [
            "search(query:kinds:)": .filtered,
        ],
        "MediaArtworkService": [
            "artworkURL(path:width:height:)": .passthrough,
            "artwork(for:kind:width:height:)": .passthrough,
            "artwork(path:width:height:)": .passthrough,
            "themePath(for:)": .passthrough,
            "themeMusicURL(path:)": .passthrough,
        ],
        "MediaDetailService": [
            "supportsWatchlist": .gated,
            "supportsRemoteSubtitleSearch": .gated,
            "supportsAdvancedSubtitleSearch": .gated,
            "mediaItem(id:)": .filtered,
            "libraryID(for:)": .passthrough,
            "searchSubtitles(itemID:language:hearingImpaired:forced:title:)": .gated,
            "installSubtitle(itemID:result:)": .gated,
            "details(for:)": .filtered,
            "fileInfo(for:)": .filtered,
            "fetchExtras(for:)": .filtered,
            "otherEditions(of:)": .filtered,
            "seasons(for:)": .filtered,
            "episodes(for:seriesID:)": .filtered,
            "allEpisodes(for:)": .filtered,
            "setPlayed(_:itemID:)": .passthrough,
            "isWatchlisted(_:)": .gated,
            "setWatchlisted(_:media:)": .gated,
            "trackSelection(itemID:versionID:)": .passthrough,
            "selectAudioTrack(id:itemID:versionID:)": .passthrough,
            "selectSubtitleTrack(id:itemID:versionID:)": .passthrough,
            "collectionItems(id:)": .filtered,
            "person(id:)": .passthrough,
            "personMedia(id:)": .filtered,
        ],
        "MediaFavoritesService": [
            "supportsFavorites": .passthrough,
            "favorites()": .filtered,
            "isFavorite(_:)": .passthrough,
            "setFavorite(_:media:)": .passthrough,
        ],
        "MediaPlaylistService": [
            "playlistEntries(id:)": .filtered,
            "canEdit(_:)": .gated,
            "editablePlaylists()": .gated,
            "createPlaylist(title:itemID:)": .gated,
            "add(itemID:toPlaylist:)": .gated,
            "remove(_:fromPlaylist:)": .gated,
            "move(_:inPlaylist:)": .gated,
            "rename(playlistID:to:)": .gated,
            "delete(playlistID:)": .gated,
        ],
        "MediaPlaybackService": [
            "serverAccessGeneration": .passthrough,
            "queue(startingWith:kind:shuffle:)": .filtered,
            "queue(startingWith:shuffle:)": .filtered,
            "queue(playlistID:startingWith:)": .filtered,
            "prepare(media:resume:quality:trackPreference:version:)": .filtered,
            "release(plan:)": .passthrough,
            "reportStarted(plan:position:isPaused:currentSelection:)": .passthrough,
            "reportProgress(plan:position:isPaused:currentSelection:)": .passthrough,
            "reportStopped(plan:position:currentSelection:)": .passthrough,
            "externalSubtitles(media:)": .passthrough,
            "reportItemPlayback(itemID:state:position:duration:isPaused:)": .passthrough,
            "pushItemPosition(itemID:position:duration:at:)": .passthrough,
            "markItemWatched(itemID:at:)": .passthrough,
            "serverWatchState(itemID:)": .passthrough,
            "serverAccessRecoveryError(from:)": .passthrough,
            "recoverServerAccessIfUnauthorized()": .passthrough,
            "forceServerAccessRecovery()": .passthrough,
        ],
        "MediaTrackSelectionMemoryService": [
            "enableTrackSelectionMemory(for:)": .passthrough,
        ],
        "MediaDownloadService": [
            "prepareDownload(itemID:quality:tracks:version:)": .filtered,
            "refreshDownloadPreparation(_:)": .passthrough,
            "downloadSidecars(itemID:tracks:versionID:isTranscoded:)": .passthrough,
            "cancelDownloadPreparation(_:)": .passthrough,
            "downloadableItems(itemID:kind:)": .filtered,
        ],
        "MediaLiveTVService": [
            "dvr": .disabled,
            "supportsServerCaptureBuffer": .disabled,
            "isAvailable()": .disabled,
            "channels()": .disabled,
            "programs(from:to:)": .disabled,
            "onNow()": .disabled,
            "setFavorite(_:channel:)": .disabled,
            "reorderFavorites(_:)": .disabled,
            "startPlayback(channel:route:)": .disabled,
        ],
        "MediaDVRService": [
            "supportsCompletedRecordings": .disabled,
            "canManageRecordings": .disabled,
            "canDeleteRecordings": .disabled,
            "upcomingRecordings()": .disabled,
            "recordingRules()": .disabled,
            "completedRecordings()": .disabled,
            "recordingTemplate(for:)": .disabled,
            "schedule(_:)": .disabled,
            "update(rule:options:)": .disabled,
            "cancel(recordingID:)": .disabled,
            "delete(ruleID:)": .disabled,
            "deleteCompleted(recordingID:)": .disabled,
            "reloadGuide()": .disabled,
        ],
        "LiveTVPlaybackSession": [
            "channel": .disabled,
            "backgroundPolicy": .disabled,
            "captureRange": .disabled,
            "source(offsetFromCaptureStart:)": .disabled,
            "report(position:isPaused:)": .disabled,
            "recover()": .disabled,
            "fallback()": .disabled,
            "stop()": .disabled,
        ],
        "MediaAuthorizationService": [
            "authorization": .gated,
        ],
        "MediaManagementService": [
            "refreshMetadata(itemID:)": .gated,
            "supportsAnalyze": .gated,
            "analyze(itemID:)": .gated,
            "scanLibrary(id:)": .gated,
            "refreshLibraryMetadata(id:)": .gated,
            "analyzeLibrary(id:)": .gated,
            "supportsLibraryTrash": .gated,
            "emptyLibraryTrash(id:)": .gated,
            "artworkKinds(for:)": .gated,
            "artworkOptions(for:kind:)": .gated,
            "selectArtwork(_:for:kind:)": .gated,
            "uploadArtwork(_:for:kind:)": .gated,
            "deletionImpact(of:)": .gated,
            "delete(_:)": .gated,
            "searchMatches(for:title:year:)": .gated,
            "applyMatch(_:to:)": .gated,
            "supportsUnmatch": .gated,
            "unmatch(itemID:)": .gated,
            "editableMetadataFields(for:)": .gated,
            "loadMetadataDraft(for:)": .gated,
            "saveMetadata(_:original:for:)": .gated,
            "metadataSuggestions(for:item:)": .gated,
            "supportsAdvancedSettings(for:)": .gated,
            "advancedSettings(itemID:)": .gated,
            "updateAdvancedSetting(_:value:itemID:)": .gated,
        ],
        // The iOS offline caches, which screens read by casting `home` and `detail` (`SafeContentServices.swift`).
        "OfflineHomeCacheReading": [
            "cachedHome()": .filtered,
        ],
        "OfflineDetailCacheReading": [
            "cachedDetails(for:)": .filtered,
            "canOpenPerson(id:)": .passthrough,
            "forgetDeletedMedia(itemID:)": .passthrough,
        ],
        // `MediaServices.accountPreferences`, stored as the provider builds it: account settings, no titles.
        "AccountPreferencesService": [
            "subtitleModes": .passthrough,
            "load()": .passthrough,
            "apply(_:)": .passthrough,
        ],
    ]
}
