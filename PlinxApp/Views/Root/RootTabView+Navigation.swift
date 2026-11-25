import PlinxCore
import PlinxUI
import SwiftUI

extension RootTabView {
    /// Every destination is shown with the services of its own server.
    func destination(for route: MainCoordinator.Route) -> some View {
        ServerScopedView(server: route.server) { services in
            routeContent(route, services: services)
        }
    }

    @ViewBuilder
    func routeContent(_ route: MainCoordinator.Route, services: MediaServices) -> some View {
        switch route {
        case let .mediaDetail(media):
            let view = PlinxMediaDetailView(
                viewModel: MediaDetailViewModel(
                    media: media,
                    services: services,
                    resolutionMode: .selectedMedia,
                    copyFinder: MediaCopyFinder(sessionManager: sessionManager),
                    onSelectCopy: mainCoordinator.showMediaDetail
                ),
                onPlay: { ratingKey, type in
                    startPlayback(ratingKey: ratingKey, type: type, services: services)
                },
                onPlayFromStart: { ratingKey, type in
                    startPlayback(
                        ratingKey: ratingKey,
                        type: type,
                        services: services,
                        shouldResumeFromOffset: false
                    )
                },
                onShuffle: { ratingKey, type in
                    startPlayback(ratingKey: ratingKey, type: type, services: services, shuffle: true)
                },
                onSelectRelated: { displayItem in
                    mainCoordinator.showMediaDetail(displayItem)
                },
                onSelectParentSeries: { series in
                    mainCoordinator.returnToSeries(series)
                },
                onRequestShellNavigationFocus: {
                    requestHeaderFocus()
                },
                contentFocusRequest: detailContentFocusRequest
            )
            tvDetailFocusRegion(view)
        case let .collectionDetail(collection):
            let view = PlinxCollectionDetailView(
                viewModel: CollectionDetailViewModel(
                    collection: collection,
                    services: services
                ),
                onSelectMedia: { displayItem in
                    mainCoordinator.showMediaDetail(displayItem)
                },
                onLongPressMedia: { displayItem in
                    presentQuickActions(for: displayItem)
                },
                onRequestShellNavigationFocus: {
                    requestHeaderFocus()
                },
                contentFocusRequest: detailContentFocusRequest
            )
            tvDetailFocusRegion(view)
        case let .playlistDetail(playlist):
            let view = PlinxPlaylistDetailView(
                viewModel: PlaylistDetailViewModel(
                    playlist: playlist,
                    services: services
                ),
                onSelectMedia: { displayItem in
                    mainCoordinator.showMediaDetail(displayItem)
                },
                onPlay: { media in
                    startPlayback(ratingKey: media.id, type: media.type, services: services)
                },
                onLongPressMedia: { displayItem in
                    presentQuickActions(for: displayItem)
                },
                onRequestShellNavigationFocus: {
                    requestHeaderFocus()
                },
                contentFocusRequest: detailContentFocusRequest
            )
            tvDetailFocusRegion(view)
        case let .hubDetail(hub):
            let view = HubDetailView(
                viewModel: HubDetailViewModel(hub: hub, services: services),
                onSelectMedia: { displayItem in
                    mainCoordinator.showMediaDetail(displayItem)
                }
            )
            tvDetailFocusRegion(withShellClearance(view))
        case let .personDetail(person, _):
            let view = PersonDetailView(
                viewModel: PersonDetailViewModel(person: person, services: services),
                onSelectMedia: { displayItem in
                    mainCoordinator.showMediaDetail(displayItem)
                }
            )
            tvDetailFocusRegion(withShellClearance(view))
        }
    }

    /// Shared Core screens draw from the top edge; on Apple TV they sit below the shell header.
    @ViewBuilder
    func withShellClearance<Content: View>(_ content: Content) -> some View {
        #if os(tvOS)
        content.safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: PlinxTVShellMetrics.contentClearance)
                .accessibilityHidden(true)
        }
        #else
        content
        #endif
    }

    @ViewBuilder
    func tvDetailFocusRegion<Content: View>(_ content: Content) -> some View {
        #if os(tvOS)
        content
            .onAppear {
                tvFocusCoordinator.activate(.detail)
            }
            .onDisappear {
                tvFocusCoordinator.activate(visibleContentRegion)
            }
        #else
        content
        #endif
    }

    func handlePrimarySelection(_ displayItem: MediaDisplayItem) {
        switch displayItem {
        case let .playable(media):
            guard let services = registry.services(for: media.identity.server) else {
                quickActionErrorMessage = String(localized: "playback.unavailable", table: "Plinx")
                return
            }
            startPlayback(ratingKey: media.id, type: media.type, services: services)
        case let .collection(collection):
            mainCoordinator.showCollectionDetail(collection)
        case let .playlist(playlist):
            mainCoordinator.showPlaylistDetail(playlist)
        }
    }

    /// Serialised through `PlaybackLaunchCoordinator`, so repeated taps never
    /// build several queues; `PlaybackLauncher` re-fetches and re-checks every
    /// queue member before the player is presented.
    func startPlayback(
        ratingKey: String,
        type: MediaKind,
        services: MediaServices,
        shuffle: Bool = false,
        shouldResumeFromOffset: Bool = true
    ) {
        guard ReleaseScreenshotCaptureMode.allowsPlayback(ratingKey: ratingKey) else {
            quickActionErrorMessage = String(localized: "playback.blockedByContentControls", table: "Plinx")
            return
        }
        let launcher = launcher(for: services)
        playbackLaunchCoordinator.launch { [playbackLaunchCoordinator] in
            await launcher.play(
                ratingKey: ratingKey,
                type: type,
                shuffle: shuffle,
                shouldResumeFromOffset: shouldResumeFromOffset,
                shouldContinue: { playbackLaunchCoordinator.isLaunching }
            )
        }
    }

    func handlePlaybackResult(_ result: PlaybackLauncher.Result) {
        switch result {
        case .started:
            break
        case .blocked:
            quickActionErrorMessage = String(localized: "playback.blockedByContentControls", table: "Plinx")
        case .failed:
            quickActionErrorMessage = String(localized: "playback.unavailable", table: "Plinx")
        }
    }
}
