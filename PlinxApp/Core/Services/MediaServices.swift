import Foundation
import Observation

struct MediaAuthorization: Equatable, Sendable {
    let isAdministrator: Bool
    let canManageSubtitles: Bool
    let canManageServer: Bool
    /// Refreshing, analyzing and scanning, artwork, matching and metadata editing.
    let canManageLibrary: Bool
    /// Server-wide right; Jellyfin can still refuse a given item through its `CanDelete`.
    let canDeleteMedia: Bool

    static let denied = MediaAuthorization(
        isAdministrator: false,
        canManageSubtitles: false,
        canManageServer: false,
        canManageLibrary: false,
        canDeleteMedia: false,
    )

    /// `allowsMediaDeletion` mirrors the server's "Allow media deletion" setting.
    static func plex(isAdministrator: Bool, allowsMediaDeletion: Bool) -> MediaAuthorization {
        MediaAuthorization(
            isAdministrator: isAdministrator,
            canManageSubtitles: true,
            canManageServer: isAdministrator,
            canManageLibrary: isAdministrator,
            canDeleteMedia: isAdministrator && allowsMediaDeletion,
        )
    }

    static func jellyfin(_ policy: JellyfinUserPolicy) -> MediaAuthorization {
        let isAdministrator = policy.isAdministrator == true
        return MediaAuthorization(
            isAdministrator: isAdministrator,
            canManageSubtitles: isAdministrator || policy.enableSubtitleManagement == true,
            canManageServer: isAdministrator,
            canManageLibrary: isAdministrator,
            canDeleteMedia: isAdministrator || policy.enableContentDeletion == true,
        )
    }
}

@MainActor
protocol MediaAuthorizationService: AnyObject {
    var authorization: MediaAuthorization { get }
}

/// A server's services. Every service is the `SafeMediaServices` wrapper of the provider's: built here, so no
/// unfiltered `MediaServices` can exist.
@MainActor
@Observable
final class MediaServices {
    let provider: MediaProvider
    let identity: ServerIdentity
    let serverName: String
    let capabilities: ProviderCapabilities
    let home: any MediaHomeService
    let library: any MediaLibraryService
    let search: any MediaSearchService
    let artwork: any MediaArtworkService
    let detail: any MediaDetailService
    let favorites: any MediaFavoritesService
    let playlists: any MediaPlaylistService
    let playback: any MediaPlaybackService
    let liveTV: any MediaLiveTVService
    let liveTVStore: LiveTVStore
    let downloads: any MediaDownloadService
    let management: any MediaManagementService
    let trackSelectionCoordinator: TrackSelectionCoordinator?
    let trackSelectionAccountIdentifier: String?
    @ObservationIgnored let versionSelectionStore: MediaVersionSelectionStore?
    @ObservationIgnored private let authorizationService: any MediaAuthorizationService
    @ObservationIgnored let contentGate: ContentSafetyGate
    /// URL of an unauthenticated endpoint used to probe the server's reachability.
    @ObservationIgnored var availabilityProbeURL: (() -> URL?)?
    @ObservationIgnored var accountPreferences: (any AccountPreferencesService)?

    /// Bumped after any playlist change, so screens listing playlists reload.
    private(set) var playlistsRevision = 0
    /// Bumped after a watched, progress or favorite change made from the app, so the home reloads this server.
    private(set) var watchStateRevision = 0
    /// Bumped after a media was changed on the server from the app (refreshed, analyzed), so screens showing it reload.
    private(set) var mediaRevision = 0
    private(set) var lastChangedMediaID: String?
    /// Media deleted from the server from the app, so pages still showing them close.
    private(set) var deletedMediaIDs: Set<String> = []

    var authorization: MediaAuthorization {
        authorizationService.authorization
    }

    func notePlaylistsChanged() {
        playlistsRevision += 1
    }

    func noteWatchStateChanged() {
        watchStateRevision += 1
    }

    func noteMediaChanged(itemID: String) {
        lastChangedMediaID = itemID
        mediaRevision += 1
    }

    func noteMediaDeleted(itemID: String) {
        deletedMediaIDs.insert(itemID)
        (detail as? any OfflineDetailCacheReading)?.forgetDeletedMedia(itemID: itemID)
        noteMediaChanged(itemID: itemID)
    }

    /// Time the server is given to apply a refresh or an analysis before screens reload the media.
    static let serverUpdateDelay: Duration = .seconds(4)

    /// For changes the server applies in the background after answering.
    func noteMediaChangeScheduled(itemID: String) {
        Task { [weak self] in
            try? await Task.sleep(for: Self.serverUpdateDelay)
            self?.noteMediaChanged(itemID: itemID)
        }
    }

    /// Any change the home shows: watch state, the media themselves, or the parent's content policy.
    var homeContentRevision: Int {
        watchStateRevision + mediaRevision + contentGate.revision
    }

    /// Scope of per-server preferences such as library browsing. A profile has one link per server, so the server and
    /// its user identify the profile's preferences for that server.
    var serverPreferencesScopeID: String {
        [
            identity.provider.rawValue,
            identity.id,
            trackSelectionAccountIdentifier ?? "default",
        ].joined(separator: "|")
    }

    init(
        provider: MediaProvider,
        identity: ServerIdentity,
        serverName: String,
        capabilities: ProviderCapabilities,
        home: any MediaHomeService,
        library: any MediaLibraryService,
        search: any MediaSearchService,
        artwork: any MediaArtworkService,
        detail: any MediaDetailService,
        favorites: any MediaFavoritesService,
        playlists: any MediaPlaylistService,
        playback: any MediaPlaybackService,
        liveTV: any MediaLiveTVService,
        downloads: any MediaDownloadService,
        authorization: any MediaAuthorizationService,
        management: (any MediaManagementService)? = nil,
        trackSelectionCoordinator: TrackSelectionCoordinator? = nil,
        trackSelectionAccountIdentifier: String? = nil,
        versionSelectionStore: MediaVersionSelectionStore? = nil,
        contentGate: ContentSafetyGate = .shared,
    ) {
        let safe = SafeMediaServices(
            gate: contentGate,
            home: home,
            library: library,
            search: search,
            artwork: artwork,
            detail: detail,
            favorites: favorites,
            playlists: playlists,
            playback: playback,
            liveTV: liveTV,
            downloads: downloads,
            authorization: authorization,
            management: management ?? UnsupportedMediaManagementService(),
        )
        self.provider = provider
        self.identity = identity
        self.serverName = serverName
        self.capabilities = capabilities
        self.home = safe.home
        self.library = safe.library
        self.search = safe.search
        self.artwork = safe.artwork
        self.detail = safe.detail
        self.favorites = safe.favorites
        self.playlists = safe.playlists
        self.playback = safe.playback
        self.liveTV = safe.liveTV
        liveTVStore = LiveTVStore(
            service: safe.liveTV,
            recentChannels: LiveTVRecentChannels(server: identity, userID: trackSelectionAccountIdentifier),
        )
        self.downloads = safe.downloads
        self.management = safe.management
        self.trackSelectionCoordinator = trackSelectionCoordinator
        self.trackSelectionAccountIdentifier = trackSelectionAccountIdentifier
        self.versionSelectionStore = versionSelectionStore
        authorizationService = safe.authorization
        self.contentGate = contentGate
    }
}
