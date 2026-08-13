import SwiftUI
import PlinxCore
import PlinxUI

extension RootTabView {
    @ViewBuilder
    func destination(for route: MainCoordinator.Route) -> some View {
        switch route {
        case let .mediaDetail(media):
            let view = PlinxMediaDetailView(
                viewModel: SafeMediaDetailViewModel(
                    inner: MediaDetailViewModel(
                        media: media,
                        context: plexApiContext,
                        resolutionMode: .selectedMedia
                    ),
                    policy: safetyPolicy
                ),
                onPlay: { ratingKey, type in
                    startPlayback(ratingKey: ratingKey, type: type)
                },
                onShuffle: { ratingKey, type in
                    startPlayback(ratingKey: ratingKey, type: type, shuffle: true)
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
                viewModel: SafeCollectionDetailViewModel(
                    inner: CollectionDetailViewModel(
                        collection: collection,
                        context: plexApiContext
                    ),
                    policy: safetyPolicy
                ),
                onSelectMedia: { displayItem in
                    mainCoordinator.showMediaDetail(displayItem)
                },
                onLongPressMedia: { displayItem in
                    selectedQuickActionMedia = displayItem
                },
                onRequestShellNavigationFocus: {
                    requestHeaderFocus()
                },
                contentFocusRequest: detailContentFocusRequest
            )
            tvDetailFocusRegion(view)
        case let .playlistDetail(playlist):
            let view = PlinxPlaylistDetailView(
                viewModel: SafePlaylistDetailViewModel(
                    inner: PlaylistDetailViewModel(
                        playlist: playlist,
                        context: plexApiContext
                    ),
                    policy: safetyPolicy
                ),
                onSelectMedia: { displayItem in
                    mainCoordinator.showMediaDetail(displayItem)
                },
                onPlay: { media in
                    startPlayback(ratingKey: media.id, type: media.type)
                },
                onLongPressMedia: { displayItem in
                    selectedQuickActionMedia = displayItem
                },
                onRequestShellNavigationFocus: {
                    requestHeaderFocus()
                },
                contentFocusRequest: detailContentFocusRequest
            )
            tvDetailFocusRegion(view)
        case let .hubDetail(hub):
            let view = HubDetailView(
                viewModel: makeHubDetailViewModel(hub: hub),
                onSelectMedia: { displayItem in
                    mainCoordinator.showMediaDetail(displayItem)
                }
            )
            #if os(tvOS)
            tvDetailFocusRegion(
                view.safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear
                        .frame(height: PlinxTVShellMetrics.contentClearance)
                        .accessibilityHidden(true)
                }
            )
            #else
            tvDetailFocusRegion(view)
            #endif
        }
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

    func makeHubDetailViewModel(hub: Hub) -> HubDetailViewModel {
        let viewModel = HubDetailViewModel(hub: hub, context: plexApiContext)
        let policy = safetyPolicy
        viewModel.itemFilter = {
            PlinxContentAuthorization.isAllowed($0, policy: policy)
        }
        return viewModel
    }

    func handlePrimarySelection(_ displayItem: MediaDisplayItem) {
        switch displayItem {
        case let .playable(media):
            startPlayback(ratingKey: media.id, type: media.type)
        case let .collection(collection):
            mainCoordinator.showCollectionDetail(collection)
        case let .playlist(playlist):
            mainCoordinator.showPlaylistDetail(playlist)
        }
    }

    func startPlayback(
        ratingKey: String,
        type: PlexItemType,
        shuffle: Bool = false,
        shouldResumeFromOffset: Bool = true
    ) {
        guard ReleaseScreenshotCaptureMode.allowsPlayback(ratingKey: ratingKey) else {
            quickActionErrorMessage = NSLocalizedString(
                "playback.blockedByContentControls",
                tableName: "Plinx",
                comment: ""
            )
            return
        }
        playbackLaunchCoordinator.launch { [launcher] in
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
            quickActionErrorMessage = NSLocalizedString(
                "playback.blockedByContentControls",
                tableName: "Plinx",
                comment: ""
            )
        case .failed:
            quickActionErrorMessage = NSLocalizedString(
                "playback.unavailable",
                tableName: "Plinx",
                comment: ""
            )
        }
    }


}
