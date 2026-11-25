import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Content-returning provider services behind the safety boundary.
//
// Each wrapper forwards to the provider's service and passes every title it
// returns through `ContentSafetyGate`. `SafeMediaServices.reviewedRequirements`
// records how each protocol requirement is treated, and
// `SafeMediaServicesTests` checks that record against the protocols.
// ─────────────────────────────────────────────────────────────────────────────

/// Reads the offline cache of a home service (iOS), so the wrapper can hand it on filtered.
@MainActor
protocol OfflineHomeCacheReading: AnyObject {
    func cachedHome() -> HomeContent?
}

/// Reads the offline cache of a detail service (iOS), so the wrapper can hand it on filtered.
@MainActor
protocol OfflineDetailCacheReading: AnyObject {
    func cachedDetails(for media: MediaItem) -> MediaDetailContent?
    func canOpenPerson(id: String) -> Bool
    func forgetDeletedMedia(itemID: String)
}

#if !os(tvOS)
    extension CachedHomeService: OfflineHomeCacheReading {}
    extension CachedDetailService: OfflineDetailCacheReading {}
#endif

// MARK: - Home

@MainActor
final class SafeHomeService: MediaHomeService, OfflineHomeCacheReading {
    private let base: any MediaHomeService
    private let gate: ContentSafetyGate
    private let hubPages = FilteredListingCache<MediaDisplayItem>()

    init(base: any MediaHomeService, gate: ContentSafetyGate) {
        self.base = base
        self.gate = gate
    }

    func loadHome(
        hiddenLibraryIDs: Set<String>,
        includesPlaylists: Bool,
        shownRowIDs: Set<String>,
        mergesNextUp: Bool,
    ) async throws -> HomeContent {
        let content = try await base.loadHome(
            hiddenLibraryIDs: hiddenLibraryIDs,
            includesPlaylists: includesPlaylists,
            shownRowIDs: shownRowIDs,
            mergesNextUp: mergesNextUp,
        )
        return gate.filter(content)
    }

    func loadWatchingRows(hiddenLibraryIDs: Set<String>, mergesNextUp: Bool) async throws -> [HomeRow] {
        try await gate.filter(base.loadWatchingRows(hiddenLibraryIDs: hiddenLibraryIDs, mergesNextUp: mergesNextUp))
    }

    /// Rows a parent can add in settings: their titles are filtered, but a row stays listed even when none is allowed
    /// today.
    func homeRowCatalog(hiddenLibraryIDs: Set<String>) async throws -> [HomeRow] {
        try await gate.filter(base.homeRowCatalog(hiddenLibraryIDs: hiddenLibraryIDs), keepsEmptiedRows: true)
    }

    func loadFeaturedCandidates(hiddenLibraryIDs: Set<String>) async throws -> [FeaturedCandidate] {
        try await gate.filter(base.loadFeaturedCandidates(hiddenLibraryIDs: hiddenLibraryIDs))
    }

    func items(in hub: Hub, startIndex: Int, limit: Int) async throws -> MediaPage<MediaDisplayItem> {
        let base = base
        let page = try await hubPages.page(
            key: [hub.id, hub.key, hub.hubKey ?? ""].joined(separator: "|"),
            startIndex: startIndex,
            limit: limit,
            policyRevision: gate.revision,
            isAllowed: { [gate] in gate.isAllowed($0) },
        ) { serverStart, serverLimit in
            let serverPage = try await base.items(in: hub, startIndex: serverStart, limit: serverLimit)
            return .init(items: serverPage.items, totalCount: serverPage.totalCount)
        }
        return MediaPage(items: page.items, startIndex: page.startIndex, totalCount: page.knownCount)
    }

    var supportsContinueWatchingRemoval: Bool {
        base.supportsContinueWatchingRemoval
    }

    func removeFromContinueWatching(itemID: String) async throws {
        try await base.removeFromContinueWatching(itemID: itemID)
    }

    func cachedHome() -> HomeContent? {
        guard let content = (base as? any OfflineHomeCacheReading)?.cachedHome() else { return nil }
        return gate.filter(content)
    }
}

// MARK: - Library

@MainActor
class SafeLibraryService: MediaLibraryService {
    /// Titles sampled for a library tile's artwork.
    static let previewSampleSize = 24

    let base: any MediaLibraryService
    let gate: ContentSafetyGate
    private let artwork: any MediaArtworkService
    private let itemPages = FilteredListingCache<MediaDisplayItem>()

    init(base: any MediaLibraryService, gate: ContentSafetyGate, artwork: any MediaArtworkService) {
        self.base = base
        self.gate = gate
        self.artwork = artwork
    }

    func libraries() async throws -> [Library] {
        try await base.libraries()
    }

    /// The provider's preview shows random, unfiltered titles of the whole library and their count. The tile instead
    /// shows the artwork of allowed titles, without a count, since the filtered size is unknown until the whole library
    /// is read.
    func preview(for library: Library) async throws -> LibraryPreview? {
        let page = try await base.items(in: library, parentID: nil, startIndex: 0, limit: Self.previewSampleSize)
        var artworks: [ArtworkResource] = []
        for item in gate.filter(page.items) where item.playableItem != nil {
            guard artworks.count < LibraryPreview.artworkCount else { break }
            do {
                if let resource = try await artwork.artwork(for: item, kind: .art, width: 1280, height: 720) {
                    artworks.append(resource)
                }
            } catch {
                if Task.isCancelled || error.isCancellation {
                    throw error
                }
            }
        }
        return LibraryPreview(artworks: artworks, itemCount: nil)
    }

    func recommended(in library: Library, mergesNextUp: Bool) async throws -> [Hub] {
        try await gate.filter(base.recommended(in: library, mergesNextUp: mergesNextUp))
    }

    func items(
        in library: Library,
        parentID: String?,
        startIndex: Int,
        limit: Int,
    ) async throws -> MediaPage<MediaDisplayItem> {
        let base = base
        let page = try await itemPages.page(
            key: [library.id, parentID ?? ""].joined(separator: "|"),
            startIndex: startIndex,
            limit: limit,
            policyRevision: gate.revision,
            isAllowed: { [gate] in gate.isAllowed($0) },
        ) { serverStart, serverLimit in
            let serverPage = try await base.items(
                in: library,
                parentID: parentID,
                startIndex: serverStart,
                limit: serverLimit,
            )
            return .init(items: serverPage.items, totalCount: serverPage.totalCount)
        }
        return MediaPage(items: page.items, startIndex: page.startIndex, totalCount: page.knownCount)
    }

    /// Containers: listed as they are, and their entries are filtered when opened.
    func collections(in library: Library) async throws -> [CollectionMediaItem] {
        try await base.collections(in: library)
    }

    /// Containers: listed as they are, and their entries are filtered when opened.
    func playlists(in library: Library) async throws -> [PlaylistMediaItem] {
        try await base.playlists(in: library)
    }
}

/// Plex libraries, which also browse through `PlexAdvancedLibraryService`.
@MainActor
final class SafePlexLibraryService: SafeLibraryService, PlexAdvancedLibraryService {
    private let advanced: any PlexAdvancedLibraryService
    private let browsePages = FilteredListingCache<LibraryBrowseItem>()
    private let collectionPages = FilteredListingCache<MediaDisplayItem>()
    private var browseMeta: [String: PlexSectionItemMeta] = [:]

    init(
        base: any MediaLibraryService & PlexAdvancedLibraryService,
        gate: ContentSafetyGate,
        artwork: any MediaArtworkService,
    ) {
        advanced = base
        super.init(base: base, gate: gate, artwork: artwork)
    }

    func advancedBrowse(
        path: String,
        queryItems: [URLQueryItem],
        startIndex: Int,
        limit: Int,
    ) async throws -> PlexAdvancedBrowsePage {
        // `includeMeta` only asks for the library's sorts and filters along the first page.
        let key = path + "?" + queryItems
            .filter { $0.name != "includeMeta" }
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&")
        let advanced = advanced
        var meta = browseMeta[key]
        let page = try await browsePages.page(
            key: key,
            startIndex: startIndex,
            limit: limit,
            policyRevision: gate.revision,
            isAllowed: { [gate] in gate.isAllowed($0) },
        ) { serverStart, serverLimit in
            let serverPage = try await advanced.advancedBrowse(
                path: path,
                queryItems: queryItems,
                startIndex: serverStart,
                limit: serverLimit,
            )
            if let pageMeta = serverPage.meta {
                meta = pageMeta
            }
            return .init(items: serverPage.items, totalCount: serverPage.totalCount)
        }
        browseMeta[key] = meta
        return PlexAdvancedBrowsePage(items: page.items, totalCount: page.knownCount, meta: meta)
    }

    func filterOptions(path: String, queryItems: [URLQueryItem]) async throws -> [PlexFilterDirectory] {
        try await advanced.filterOptions(path: path, queryItems: queryItems)
    }

    /// The server counts every title under each letter, blocked ones included, so jumping by letter would land on the
    /// wrong position of the filtered listing. Without characters the screens hide the letter index.
    func sectionCharacters(
        path _: String,
        queryItems _: [URLQueryItem],
    ) async throws -> [PlexAdvancedSectionCharacter] {
        []
    }

    /// See `sectionCharacters(path:queryItems:)`.
    func collectionCharacters(sectionID _: Int) async throws -> [PlexAdvancedSectionCharacter] {
        []
    }

    func collectionPage(sectionID: Int, startIndex: Int, limit: Int) async throws -> MediaPage<MediaDisplayItem> {
        let advanced = advanced
        let page = try await collectionPages.page(
            key: String(sectionID),
            startIndex: startIndex,
            limit: limit,
            policyRevision: gate.revision,
            isAllowed: { [gate] in gate.isAllowed($0) },
        ) { serverStart, serverLimit in
            let serverPage = try await advanced.collectionPage(
                sectionID: sectionID,
                startIndex: serverStart,
                limit: serverLimit,
            )
            return .init(items: serverPage.items, totalCount: serverPage.totalCount)
        }
        return MediaPage(items: page.items, startIndex: page.startIndex, totalCount: page.knownCount)
    }
}

/// Jellyfin libraries, which also browse through `AdvancedLibraryBrowseService`.
@MainActor
final class SafeBrowseLibraryService: SafeLibraryService, AdvancedLibraryBrowseService {
    private let browse: any AdvancedLibraryBrowseService
    private let browsePages = FilteredListingCache<MediaDisplayItem>()

    init(
        base: any MediaLibraryService & AdvancedLibraryBrowseService,
        gate: ContentSafetyGate,
        artwork: any MediaArtworkService,
    ) {
        browse = base
        super.init(base: base, gate: gate, artwork: artwork)
    }

    func browseItems(
        in library: Library,
        parentID: String?,
        query: LibraryBrowseQuery,
        startIndex: Int,
        limit: Int,
    ) async throws -> MediaPage<MediaDisplayItem> {
        let browse = browse
        let page = try await browsePages.page(
            key: [library.id, parentID ?? "", String(describing: query)].joined(separator: "|"),
            startIndex: startIndex,
            limit: limit,
            policyRevision: gate.revision,
            isAllowed: { [gate] in gate.isAllowed($0) },
        ) { serverStart, serverLimit in
            let serverPage = try await browse.browseItems(
                in: library,
                parentID: parentID,
                query: query,
                startIndex: serverStart,
                limit: serverLimit,
            )
            return .init(items: serverPage.items, totalCount: serverPage.totalCount)
        }
        return MediaPage(items: page.items, startIndex: page.startIndex, totalCount: page.knownCount)
    }

    func browseFilterOptions(in library: Library) async throws -> LibraryBrowseFilterOptions {
        try await browse.browseFilterOptions(in: library)
    }
}

// MARK: - Search

@MainActor
final class SafeSearchService: MediaSearchService {
    private let base: any MediaSearchService
    private let gate: ContentSafetyGate

    init(base: any MediaSearchService, gate: ContentSafetyGate) {
        self.base = base
        self.gate = gate
    }

    func search(query: String, kinds: Set<MediaKind>) async throws -> [MediaDisplayItem] {
        try await gate.filter(base.search(query: query, kinds: kinds))
    }
}

// MARK: - Detail

@MainActor
final class SafeDetailService: MediaDetailService, OfflineDetailCacheReading {
    private let base: any MediaDetailService
    private let gate: ContentSafetyGate

    init(base: any MediaDetailService, gate: ContentSafetyGate) {
        self.base = base
        self.gate = gate
    }

    /// The watchlist writes to the account (plex.tv): parent-only, like playlist edits.
    var supportsWatchlist: Bool {
        gate.isParentUnlocked && base.supportsWatchlist
    }

    /// Downloading subtitles writes to the server: parent-only.
    var supportsRemoteSubtitleSearch: Bool {
        gate.isParentUnlocked && base.supportsRemoteSubtitleSearch
    }

    var supportsAdvancedSubtitleSearch: Bool {
        gate.isParentUnlocked && base.supportsAdvancedSubtitleSearch
    }

    /// A blocked title is "not found".
    func mediaItem(id: String) async throws -> MediaItem {
        try await gate.requireAllowed(base.mediaItem(id: id))
    }

    func libraryID(for media: MediaItem) async throws -> String? {
        try await base.libraryID(for: media)
    }

    func searchSubtitles(
        itemID: String,
        language: String,
        hearingImpaired: Bool,
        forced: Bool,
        title: String?,
    ) async throws -> [RemoteSubtitleResult] {
        guard gate.isParentUnlocked else { throw ContentSafetyError.parentApprovalRequired }
        return try await base.searchSubtitles(
            itemID: itemID,
            language: language,
            hearingImpaired: hearingImpaired,
            forced: forced,
            title: title,
        )
    }

    func installSubtitle(itemID: String, result: RemoteSubtitleResult) async throws {
        guard gate.isParentUnlocked else { throw ContentSafetyError.parentApprovalRequired }
        try await base.installSubtitle(itemID: itemID, result: result)
    }

    func details(for media: MediaItem) async throws -> MediaDetailContent {
        _ = try gate.requireAllowed(media)
        return try await gate.filter(base.details(for: media))
    }

    func fileInfo(for media: MediaItem) async throws -> MediaFileInfo? {
        _ = try gate.requireAllowed(media)
        return try await base.fileInfo(for: media)
    }

    func fetchExtras(for media: MediaItem) async throws -> [MediaItem] {
        try await gate.filter(base.fetchExtras(for: media))
    }

    func otherEditions(of media: MediaItem) async throws -> [MediaItem] {
        try await gate.filter(base.otherEditions(of: media))
    }

    func seasons(for series: MediaItem) async throws -> [MediaItem] {
        _ = try gate.requireAllowed(series)
        return try await gate.filter(base.seasons(for: series))
    }

    /// Only the episodes are judged: a season often carries no rating of its own.
    func episodes(for season: MediaItem, seriesID: String?) async throws -> [MediaItem] {
        try await gate.filter(base.episodes(for: season, seriesID: seriesID))
    }

    func allEpisodes(for series: MediaItem) async throws -> [MediaItem] {
        _ = try gate.requireAllowed(series)
        return try await gate.filter(base.allEpisodes(for: series))
    }

    func setPlayed(_ played: Bool, itemID: String) async throws {
        try await base.setPlayed(played, itemID: itemID)
    }

    func isWatchlisted(_ media: MediaItem) async throws -> Bool {
        guard gate.isParentUnlocked else { return false }
        return try await base.isWatchlisted(media)
    }

    func setWatchlisted(_ watchlisted: Bool, media: MediaItem) async throws {
        guard gate.isParentUnlocked else { throw ContentSafetyError.parentApprovalRequired }
        try await base.setWatchlisted(watchlisted, media: media)
    }

    func trackSelection(itemID: String, versionID: String?) async throws -> MediaTrackSelection {
        try await base.trackSelection(itemID: itemID, versionID: versionID)
    }

    func selectAudioTrack(id: Int, itemID: String, versionID: String?) async throws {
        try await base.selectAudioTrack(id: id, itemID: itemID, versionID: versionID)
    }

    func selectSubtitleTrack(id: Int?, itemID: String, versionID: String?) async throws {
        try await base.selectSubtitleTrack(id: id, itemID: itemID, versionID: versionID)
    }

    func collectionItems(id: String) async throws -> [MediaDisplayItem] {
        try await gate.filter(base.collectionItems(id: id))
    }

    func person(id: String) async throws -> Person {
        try await base.person(id: id)
    }

    func personMedia(id: String) async throws -> [MediaDisplayItem] {
        try await gate.filter(base.personMedia(id: id))
    }

    // MARK: Offline cache

    func cachedDetails(for media: MediaItem) -> MediaDetailContent? {
        guard gate.isAllowed(media),
              let content = (base as? any OfflineDetailCacheReading)?.cachedDetails(for: media)
        else { return nil }
        return try? gate.filter(content)
    }

    func canOpenPerson(id: String) -> Bool {
        (base as? any OfflineDetailCacheReading)?.canOpenPerson(id: id) ?? true
    }

    func forgetDeletedMedia(itemID: String) {
        (base as? any OfflineDetailCacheReading)?.forgetDeletedMedia(itemID: itemID)
    }
}

// MARK: - Favorites

@MainActor
final class SafeFavoritesService: MediaFavoritesService {
    private let base: any MediaFavoritesService
    private let gate: ContentSafetyGate

    init(base: any MediaFavoritesService, gate: ContentSafetyGate) {
        self.base = base
        self.gate = gate
    }

    var supportsFavorites: Bool {
        base.supportsFavorites
    }

    func favorites() async throws -> [MediaItem] {
        try await gate.filter(base.favorites())
    }

    func isFavorite(_ media: MediaItem) async throws -> Bool {
        try await base.isFavorite(media)
    }

    /// Favoriting is a harmless per-user write, allowed to kids.
    func setFavorite(_ favorite: Bool, media: MediaItem) async throws {
        try await base.setFavorite(favorite, media: media)
    }
}

// MARK: - Playlists

/// Kids see playlists with their blocked entries removed; editing playlists is parent-only.
@MainActor
final class SafePlaylistService: MediaPlaylistService {
    private let base: any MediaPlaylistService
    private let gate: ContentSafetyGate

    init(base: any MediaPlaylistService, gate: ContentSafetyGate) {
        self.base = base
        self.gate = gate
    }

    func playlistEntries(id: String) async throws -> [PlaylistEntry] {
        try await gate.filter(base.playlistEntries(id: id))
    }

    func canEdit(_ playlist: PlaylistMediaItem) async throws -> Bool {
        guard gate.isParentUnlocked else { return false }
        return try await base.canEdit(playlist)
    }

    func editablePlaylists() async throws -> [PlaylistMediaItem] {
        guard gate.isParentUnlocked else { return [] }
        return try await base.editablePlaylists()
    }

    func createPlaylist(title: String, itemID: String) async throws {
        try requireParent()
        try await base.createPlaylist(title: title, itemID: itemID)
    }

    func add(itemID: String, toPlaylist playlistID: String) async throws {
        try requireParent()
        try await base.add(itemID: itemID, toPlaylist: playlistID)
    }

    func remove(_ entry: PlaylistEntry, fromPlaylist playlistID: String) async throws {
        try requireParent()
        try await base.remove(entry, fromPlaylist: playlistID)
    }

    func move(_ move: PlaylistEntryMove, inPlaylist playlistID: String) async throws {
        try requireParent()
        try await base.move(move, inPlaylist: playlistID)
    }

    func rename(playlistID: String, to title: String) async throws {
        try requireParent()
        try await base.rename(playlistID: playlistID, to: title)
    }

    func delete(playlistID: String) async throws {
        try requireParent()
        try await base.delete(playlistID: playlistID)
    }

    private func requireParent() throws {
        guard gate.isParentUnlocked else { throw ContentSafetyError.parentApprovalRequired }
    }
}

// MARK: - Playback

/// Every queue is filtered, and nothing is prepared for a blocked title. `PlinxPlaybackLauncher` stays the final
/// check before the player opens.
@MainActor
class SafePlaybackService: MediaPlaybackService {
    let base: any MediaPlaybackService
    let gate: ContentSafetyGate

    init(base: any MediaPlaybackService, gate: ContentSafetyGate) {
        self.base = base
        self.gate = gate
    }

    var serverAccessGeneration: Int {
        base.serverAccessGeneration
    }

    func queue(startingWith itemID: String, kind: MediaKind, shuffle: Bool) async throws -> PlaybackQueue {
        try await gate.filter(base.queue(startingWith: itemID, kind: kind, shuffle: shuffle))
    }

    func queue(startingWith media: MediaItem, shuffle: Bool) async throws -> PlaybackQueue {
        _ = try gate.requireAllowed(media)
        return try await gate.filter(base.queue(startingWith: media, shuffle: shuffle))
    }

    func queue(playlistID: String, startingWith entry: PlaylistEntry) async throws -> PlaybackQueue {
        guard gate.isAllowed(entry.media) else { throw ContentSafetyError.blocked }
        return try await gate.filter(base.queue(playlistID: playlistID, startingWith: entry))
    }

    func prepare(
        media: MediaItem,
        resume: Bool,
        quality: TranscodeQualityPreset,
        trackPreference: MediaTrackPreference?,
        version: MediaVersionRequest,
    ) async throws -> PlaybackPlan {
        _ = try gate.requireAllowed(media)
        let plan = try await base.prepare(
            media: media,
            resume: resume,
            quality: quality,
            trackPreference: trackPreference,
            version: version,
        )
        guard gate.isAllowed(plan.media) else {
            await base.release(plan: plan)
            throw ContentSafetyError.blocked
        }
        return plan
    }

    func release(plan: PlaybackPlan) async {
        await base.release(plan: plan)
    }

    /// External players would bypass every content check and the volume cap.
    func externalPlaybackTarget(
        for _: MediaItem,
        version _: MediaVersionRequest,
    ) async throws -> ExternalPlaybackTarget {
        throw ContentSafetyError.unavailable
    }

    func reportStarted(
        plan: PlaybackPlan,
        position: TimeInterval,
        isPaused: Bool,
        currentSelection: PlaybackStreamSelection?,
    ) async throws {
        try await base.reportStarted(
            plan: plan,
            position: position,
            isPaused: isPaused,
            currentSelection: currentSelection,
        )
    }

    func reportProgress(
        plan: PlaybackPlan,
        position: TimeInterval,
        isPaused: Bool,
        currentSelection: PlaybackStreamSelection?,
    ) async throws {
        try await base.reportProgress(
            plan: plan,
            position: position,
            isPaused: isPaused,
            currentSelection: currentSelection,
        )
    }

    func reportStopped(
        plan: PlaybackPlan,
        position: TimeInterval,
        currentSelection: PlaybackStreamSelection?,
    ) async throws {
        try await base.reportStopped(plan: plan, position: position, currentSelection: currentSelection)
    }

    func externalSubtitles(media: MediaItem) async throws -> [PlayerExternalSubtitle] {
        try await base.externalSubtitles(media: media)
    }

    func reportItemPlayback(
        itemID: String,
        state: ItemPlaybackReportState,
        position: TimeInterval,
        duration: TimeInterval?,
        isPaused: Bool,
    ) async throws {
        try await base.reportItemPlayback(
            itemID: itemID,
            state: state,
            position: position,
            duration: duration,
            isPaused: isPaused,
        )
    }

    func pushItemPosition(itemID: String, position: TimeInterval, duration: TimeInterval?, at date: Date) async throws {
        try await base.pushItemPosition(itemID: itemID, position: position, duration: duration, at: date)
    }

    func markItemWatched(itemID: String, at date: Date) async throws {
        try await base.markItemWatched(itemID: itemID, at: date)
    }

    func serverWatchState(itemID: String) async throws -> ServerItemWatchState {
        try await base.serverWatchState(itemID: itemID)
    }

    func serverAccessRecoveryError(from error: Error) -> MediaServerAccessRecoveryError? {
        base.serverAccessRecoveryError(from: error)
    }

    func recoverServerAccessIfUnauthorized() async throws -> Bool {
        try await base.recoverServerAccessIfUnauthorized()
    }

    func forceServerAccessRecovery() async throws {
        try await base.forceServerAccessRecovery()
    }
}

/// Playback services that also remember track choices (Jellyfin), so callers still find that ability.
@MainActor
final class SafeTrackMemoryPlaybackService: SafePlaybackService, MediaTrackSelectionMemoryService {
    private let memory: any MediaTrackSelectionMemoryService

    init(base: any MediaPlaybackService & MediaTrackSelectionMemoryService, gate: ContentSafetyGate) {
        memory = base
        super.init(base: base, gate: gate)
    }

    func enableTrackSelectionMemory(for kind: PlaybackTrackKind) async throws {
        try await memory.enableTrackSelectionMemory(for: kind)
    }
}

// MARK: - Downloads

@MainActor
final class SafeDownloadService: MediaDownloadService {
    private let base: any MediaDownloadService
    private let gate: ContentSafetyGate

    init(base: any MediaDownloadService, gate: ContentSafetyGate) {
        self.base = base
        self.gate = gate
    }

    /// The title is only known once the server answers; a blocked one is cancelled on the server and refused.
    func prepareDownload(
        itemID: String,
        quality: TranscodeQualityPreset,
        tracks: MediaTrackPreference,
        version: MediaVersionRequest,
    ) async throws -> MediaDownloadPreparation {
        let preparation = try await base.prepareDownload(
            itemID: itemID,
            quality: quality,
            tracks: tracks,
            version: version,
        )
        guard gate.isAllowed(preparation.media) else {
            if let reference = preparation.remoteReference {
                await base.cancelDownloadPreparation(reference)
            }
            throw ContentSafetyError.blocked
        }
        return preparation
    }

    func refreshDownloadPreparation(
        _ reference: MediaDownloadRemoteReference,
    ) async throws -> MediaDownloadPreparationUpdate {
        try await base.refreshDownloadPreparation(reference)
    }

    func downloadSidecars(
        itemID: String,
        tracks: MediaTrackPreference,
        versionID: String?,
        isTranscoded: Bool,
    ) async throws -> [MediaDownloadSidecar] {
        try await base.downloadSidecars(
            itemID: itemID,
            tracks: tracks,
            versionID: versionID,
            isTranscoded: isTranscoded,
        )
    }

    func cancelDownloadPreparation(_ reference: MediaDownloadRemoteReference) async {
        await base.cancelDownloadPreparation(reference)
    }

    func downloadableItems(itemID: String, kind: MediaKind) async throws -> [MediaItem] {
        try await gate.filter(base.downloadableItems(itemID: itemID, kind: kind))
    }
}
