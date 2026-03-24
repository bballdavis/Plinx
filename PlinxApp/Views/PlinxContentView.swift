import SwiftUI
import PlinxUI

struct PlinxContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(DownloadManager.self) private var downloadManager
    @EnvironmentObject private var mainCoordinator: MainCoordinator
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: downloadManager.isOffline) { _, isOffline in
            // When connectivity is restored, re-hydrate the session so the app
            // automatically returns to online mode rather than staying stuck on
            // a sign-in or loading screen after the offline period.
            // Always re-validate even if the previous status was .ready — a once-ready
            // session can have stale tokens or a temporarily unreachable server.
            guard !isOffline else { return }
            guard sessionManager.status != .hydrating else { return }
            Task {
                await sessionManager.hydrate()
                // If hydration failed and left us signed-out (with isOffline still
                // false, because the plexConnectionUnavailable notification was
                // suppressed during hydration), re-mark offline so we stay on the
                // offline screen instead of bouncing to the sign-in view.
                if sessionManager.status == .signedOut {
                    downloadManager.markOfflineDueToConnectionFailure()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await downloadManager.recheckNetworkStatus() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .plexConnectionUnavailable)) { _ in
            // While the session is actively hydrating (a reconnect attempt is in
            // progress), a network failure from one of the auth calls must NOT
            // immediately cancel the reconnect by flipping isOffline back to true.
            // The hydrate path already handles its own failure state; if it truly
            // can't connect, subsequent non-hydration Plex calls will re-trigger this.
            guard sessionManager.status != .hydrating else { return }
            downloadManager.markOfflineDueToConnectionFailure()
        }
        .fullScreenCover(item: $mainCoordinator.selectedPlayQueue) { playQueue in
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
                    viewModel: SignInViewModel(
                        sessionManager: sessionManager,
                        context: plexApiContext,
                    ),
                )
            case DownloadUITestFixtures.screenName:
                NavigationStack {
                    PlinxDownloadsGridView()
                }
            default:
                sessionContent
            }
        } else {
            sessionContent
        }
    }

    @ViewBuilder
    private var sessionContent: some View {
        if downloadManager.isOffline {
            OfflineRootView()
        } else {
            switch sessionManager.status {
            case .hydrating:
                PlinxBrandedLoadingView(
                    preferredLogoAssetName: "LogoStackedFullWhite",
                    showsProgressView: false,
                    fillsBackground: false
                )
            case .signedOut:
                SignInView(
                    viewModel: SignInViewModel(
                        sessionManager: sessionManager,
                        context: plexApiContext,
                    ),
                )
            case .needsProfileSelection:
                NavigationStack {
                    ProfileSwitcherView(
                        viewModel: ProfileSwitcherViewModel(
                            context: plexApiContext,
                            sessionManager: sessionManager,
                        ),
                    )
                }
            case .needsServerSelection:
                NavigationStack {
                    SelectServerView(
                        viewModel: ServerSelectionViewModel(
                            sessionManager: sessionManager,
                            context: plexApiContext,
                        ),
                    )
                }
            case .ready:
                RootTabView()
                    .id(sessionManager.plexServer?.clientIdentifier ?? "no-server")
            }
        }
    }
}
