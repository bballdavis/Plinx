import SwiftUI
import PlinxUI

struct PlinxContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(\.safetyPolicy) private var safetyPolicy
    @EnvironmentObject private var mainCoordinator: MainCoordinator

    private var uiTestScreenOverride: String? {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else {
            return nil
        }
        return ProcessInfo.processInfo.environment["PLINX_UI_TEST_SCREEN"]
    }

    var body: some View {
        ZStack {
            // Match the ambient launch treatment during hydration to eliminate
            // a visible flash between the storyboard and the SwiftUI tree.
            if sessionManager.status == .hydrating {
                PlinxAmbientBackground(intensity: .hero)
            } else {
                Color.appBackground.ignoresSafeArea()
            }

            rootContent
        }
        .fullScreenCover(item: $mainCoordinator.selectedPlayQueue) { playQueue in
            PlinxPlayerPlaybackView(
                viewModel: PlayerViewModel(
                    playQueue: playQueue,
                    context: plexApiContext,
                    shouldResumeFromOffset: mainCoordinator.shouldResumeFromOffset
                ),
                onExit: {
                    mainCoordinator.resetPlayer()
                },
                isPlaybackAuthorized: { item in
                    PlinxContentAuthorization.isAllowed(item, policy: safetyPolicy)
                }
            )
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
                playerSettingsPreview
            case "loadingGallery":
                loadingGalleryPreview
            case "homeLoading":
                homeLoadingPreview
            case "playerBuffering":
                playerBufferingPreview
            case "refreshLoading":
                refreshLoadingPreview
            case "settings":
                NavigationStack {
                    PlinxSettingsView(isUnlocked: true)
                }
            case "profileSwitcher":
                NavigationStack {
                    #if os(tvOS)
                    ProfileSwitcherTVView(
                        viewModel: ProfileSwitcherViewModel(
                            context: plexApiContext,
                            sessionManager: sessionManager
                        )
                    )
                    #else
                    ProfileSwitcherView(
                        viewModel: ProfileSwitcherViewModel(
                            context: plexApiContext,
                            sessionManager: sessionManager
                        )
                    )
                    #endif
                }
            case "selectServer":
                NavigationStack {
                    #if os(tvOS)
                    SelectServerTVView(
                        viewModel: ServerSelectionViewModel(
                            sessionManager: sessionManager,
                            context: plexApiContext
                        )
                    )
                    #else
                    SelectServerView(
                        viewModel: ServerSelectionViewModel(
                            sessionManager: sessionManager,
                            context: plexApiContext
                        )
                    )
                    #endif
                }
            #if !os(tvOS)
            case DownloadUITestFixtures.screenName:
                PlinxDownloadsGridView()
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

                Text("player.settings.previewUnavailable", tableName: "Plinx")
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
            onSelectAudio: { _ in },
            onSelectSubtitle: { _ in },
            onClose: {}
        )
        #endif
    }

    private var loadingGalleryPreview: some View {
        ScrollView {
            VStack(spacing: 36) {
                Text("Plinx loading")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                HStack(alignment: .bottom, spacing: 32) {
                    PlinxLoadingIndicator(
                        size: .compact,
                        surface: .transparent,
                        label: "Compact",
                        accessibilityIdentifier: "loading.indicator.compact"
                    )

                    PlinxLoadingIndicator(
                        size: .regular,
                        surface: .glass,
                        label: "Regular",
                        accessibilityIdentifier: "loading.indicator.regular"
                    )
                }

                PlinxLoadingIndicator(
                    size: .hero,
                    surface: .video,
                    label: "Buffering…",
                    accessibilityIdentifier: "loading.indicator.hero"
                )
            }
            .frame(maxWidth: .infinity)
            .padding(40)
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    private var playerBufferingPreview: some View {
        ZStack {
            Image("LaunchGradient")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            Color.black.opacity(0.34)
                .ignoresSafeArea()

            PlinxVideoBufferingOverlay()
        }
    }

    private var homeLoadingPreview: some View {
        PlinxBrandedLoadingView(
            logoAsset: .markColor,
            logoAccessibilityIdentifier: "home.loading.logo",
            presentation: .heroIdentity,
            fillsBackground: true
        )
    }

    private var refreshLoadingPreview: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Pull to refresh")
                    .font(.title.bold())
                    .foregroundStyle(.white)

                Text("Deterministic Plinx refresh-indicator test route")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .plinxRefreshable {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    @ViewBuilder
    private var sessionContent: some View {
        switch sessionManager.status {
        case .hydrating:
            PlinxBrandedLoadingView(
                logoAsset: .lockupOnDark,
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
                .id(sessionRootIdentity)
        }
    }

    private var sessionRootIdentity: String {
        let server = sessionManager.plexServer?.clientIdentifier ?? "no-server"
        let profile = sessionManager.user?.uuid
            ?? sessionManager.user?.id.map(String.init)
            ?? sessionManager.user?.username
            ?? "no-profile"
        return "\(server)|\(profile)"
    }
}
