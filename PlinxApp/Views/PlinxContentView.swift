import SwiftUI
import PlinxUI

struct PlinxContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext
    @EnvironmentObject private var mainCoordinator: MainCoordinator

    private var uiTestScreenOverride: String? {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else {
            return nil
        }
        return ProcessInfo.processInfo.environment["PLINX_UI_TEST_SCREEN"]
    }

    var body: some View {
        ZStack {
            // Match the launch screen colour during hydration to eliminate the
            // black flash between the storyboard splash and the SwiftUI tree.
            if sessionManager.status == .hydrating {
                LinearGradient.plinxBrandGreen.ignoresSafeArea()
            } else {
                Color.appBackground.ignoresSafeArea()
            }

            rootContent
        }
        .fullScreenCover(item: $mainCoordinator.selectedPlayQueue) { playQueue in
            #if os(tvOS)
            PlayerTVWrapper(
                viewModel: PlayerViewModel(
                    playQueue: playQueue,
                    context: plexApiContext,
                    shouldResumeFromOffset: mainCoordinator.shouldResumeFromOffset
                ),
                onExit: {
                    mainCoordinator.resetPlayer()
                }
            )
            #else
            PlayerWrapper(
                viewModel: PlayerViewModel(
                    playQueue: playQueue,
                    context: plexApiContext,
                    shouldResumeFromOffset: mainCoordinator.shouldResumeFromOffset
                )
            )
            .onDisappear {
                mainCoordinator.resetPlayer()
            }
            #endif
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if let uiTestScreenOverride {
            switch uiTestScreenOverride {
            case "parentalGate":
                ParentalGateView(onAllowed: {})
            case "signIn":
                SignInView(
                    viewModel: PlinxSignInViewModel(
                        sessionManager: sessionManager,
                        context: plexApiContext,
                    ),
                )
            case "playerSettings":
                NavigationStack {
                    playerSettingsPreview
                }
            #if !os(tvOS)
            case DownloadUITestFixtures.screenName:
                NavigationStack {
                    PlinxDownloadsGridView()
                }
            #endif
            default:
                sessionContent
            }
        } else {
            sessionContent
        }
    }

    private var playerSettingsPreview: some View {
        #if os(tvOS)
        return AnyView(
            VStack(spacing: 12) {
                Image(systemName: "captions.bubble.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text("Player settings preview unavailable on tvOS")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(Color.appBackground.ignoresSafeArea())
        )
        #else
        let audioTracks = [
            PlaybackSettingsTrack(
                track: PlayerTrack(
                    id: 1,
                    ffIndex: 1,
                    type: .audio,
                    title: "English",
                    language: "en",
                    codec: "AAC",
                    isDefault: true,
                    isForced: false,
                    isHearingImpaired: false,
                    isCommentary: false,
                    isExternal: false,
                    isSelected: true
                ),
                plexStream: nil
            ),
            PlaybackSettingsTrack(
                track: PlayerTrack(
                    id: 2,
                    ffIndex: 2,
                    type: .audio,
                    title: "Spanish",
                    language: "es",
                    codec: "AAC",
                    isDefault: false,
                    isForced: false,
                    isHearingImpaired: false,
                    isCommentary: false,
                    isExternal: false,
                    isSelected: false
                ),
                plexStream: nil
            ),
        ]

        let subtitleTracks = [
            PlaybackSettingsTrack(
                track: PlayerTrack(
                    id: 11,
                    ffIndex: 11,
                    type: .subtitle,
                    title: "English CC",
                    language: "en",
                    codec: "SRT",
                    isDefault: true,
                    isForced: false,
                    isHearingImpaired: true,
                    isCommentary: false,
                    isExternal: false,
                    isSelected: false
                ),
                plexStream: nil
            )
        ]

        return PlaybackSettingsView(
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks,
            selectedAudioTrackID: 1,
            selectedSubtitleTrackID: 11,
            playbackRate: 1,
            onSelectAudio: { _ in },
            onSelectSubtitle: { _ in },
            onSelectPlaybackRate: { _ in },
            onClose: {}
        )
        #endif
    }

    @ViewBuilder
    private var sessionContent: some View {
        switch sessionManager.status {
        case .hydrating:
            PlinxBrandedLoadingView(
                preferredLogoAssetName: "LogoStackedFullWhite",
                showsProgressView: false,
                fillsBackground: false
            )
        case .signedOut:
            SignInView(
                viewModel: PlinxSignInViewModel(
                    sessionManager: sessionManager,
                    context: plexApiContext,
                ),
            )
        case .needsProfileSelection:
            NavigationStack {
                #if os(tvOS)
                ProfileSwitcherTVView(
                    viewModel: ProfileSwitcherViewModel(
                        context: plexApiContext,
                        sessionManager: sessionManager,
                    )
                )
                #else
                ProfileSwitcherView(
                    viewModel: ProfileSwitcherViewModel(
                        context: plexApiContext,
                        sessionManager: sessionManager,
                    ),
                )
                #endif
            }
        case .needsServerSelection:
            NavigationStack {
                #if os(tvOS)
                SelectServerTVView(
                    viewModel: ServerSelectionViewModel(
                        sessionManager: sessionManager,
                        context: plexApiContext,
                    )
                )
                #else
                SelectServerView(
                    viewModel: ServerSelectionViewModel(
                        sessionManager: sessionManager,
                        context: plexApiContext,
                    ),
                )
                #endif
            }
        case .ready:
            RootTabView()
                .id(sessionManager.plexServer?.clientIdentifier ?? "no-server")
        }
    }
}
