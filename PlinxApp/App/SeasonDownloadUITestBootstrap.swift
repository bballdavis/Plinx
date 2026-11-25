import SwiftUI

#if DEBUG && !os(tvOS)
/// UI-test route `seasonDownloadOffline`: the detail page of a season whose
/// server cannot be reached, with its episodes already loaded, to check that
/// the season download picker lists and selects them without a connection.
struct SeasonDownloadUITestHarness: View {
    @State private var services: MediaServices

    init() {
        _services = State(initialValue: SeasonDownloadFixture.makeUnreachableServices())
    }

    var body: some View {
        NavigationStack {
            NavigationLink {
                SeasonDownloadFixtureView(services: services)
                    .environment(services)
            } label: {
                Text(verbatim: "More Info")
            }
            .accessibilityIdentifier("season.fixture.moreInfo")
        }
    }
}

/// Fixture server and titles for `SeasonDownloadUITestHarness`.
@MainActor
enum SeasonDownloadFixture {
    static let server = ServerIdentity(provider: .plex, id: "plinx-ui-test-season-server")
    static let profileID = "ui-test-profile"

    /// Real Plex services, wrapped by the safety boundary like every
    /// `MediaServices`, for a server that was never connected: every request
    /// fails as it would without a network. Favorites live in a separate
    /// defaults suite so the fixture never touches the family's.
    static func makeUnreachableServices() -> MediaServices {
        let context = PlexAPIContext()
        let adapter = PlexMediaServiceAdapter(context: context, server: server)
        let favoritesDefaults = UserDefaults(suiteName: "plinx.uiTest.seasonDownload") ?? UserDefaults()
        let services = MediaServices(
            provider: .plex,
            identity: server,
            serverName: "Fixture Server",
            capabilities: .plex,
            home: adapter,
            library: adapter,
            search: adapter,
            artwork: adapter,
            detail: adapter,
            favorites: PlexFavoritesService(
                context: context,
                store: FavoritesStore(userDefaults: favoritesDefaults),
                scope: .plex(serverID: server.id, profileID: profileID)
            ),
            playlists: PlexPlaylistService(context: context, server: server),
            playback: adapter,
            liveTV: PlexLiveTVService(context: context),
            downloads: adapter,
            authorization: adapter,
            trackSelectionAccountIdentifier: profileID
        )
        adapter.services = services
        return services
    }

    static func mediaItem(
        id: String,
        title: String,
        type: MediaKind,
        parentRatingKey: String?,
        grandparentRatingKey: String? = nil,
        index: Int
    ) -> MediaItem {
        MediaItem(
            id: id,
            identity: MediaIdentity(server: server, itemID: id),
            guid: "fixture://\(id)",
            summary: nil,
            title: title,
            type: type,
            parentRatingKey: parentRatingKey,
            grandparentRatingKey: grandparentRatingKey,
            genres: [],
            year: nil,
            duration: 1_200,
            videoResolution: nil,
            rating: nil,
            ratings: [],
            contentRating: "TV-Y",
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
            grandparentTitle: "Fixture Show",
            parentTitle: "Season 1",
            parentIndex: 1,
            index: index,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil
        )
    }
}

private struct SeasonDownloadFixtureView: View {
    @State private var viewModel: MediaDetailViewModel

    init(services: MediaServices) {
        let season = SeasonDownloadFixture.mediaItem(
            id: "season-1",
            title: "Season 1",
            type: .season,
            parentRatingKey: "show-1",
            index: 1
        )
        let model = MediaDetailViewModel(
            media: PlayableMediaItem(mediaItem: season)!,
            services: services,
            resolutionMode: .selectedMedia
        )
        // The download picker lists the seasons it can offer; a season page
        // offers itself, with the episodes loaded before the server went away.
        model.seasons = [season]
        model.selectedSeasonId = season.id
        model.episodes = (1 ... 3).map { index in
            SeasonDownloadFixture.mediaItem(
                id: "episode-\(index)",
                title: "Fixture Episode \(index)",
                type: .episode,
                parentRatingKey: season.id,
                grandparentRatingKey: "show-1",
                index: index
            )
        }
        _viewModel = State(initialValue: model)
    }

    var body: some View {
        PlinxMediaDetailView(
            viewModel: viewModel,
            onPlay: { _, _ in },
            onShuffle: { _, _ in },
            onSelectRelated: { _ in }
        )
    }
}
#endif
