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
    @State private var offlineReconnectUITestState = "offline"

    private var uiTestScreenOverride: String? {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else {
            return nil
        }
        return ProcessInfo.processInfo.environment["PLINX_UI_TEST_SCREEN"]
    }

    private var isOfflineReconnectUITest: Bool {
        uiTestScreenOverride == OfflineReconnectUITestFixtures.screenName
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
        .overlay(alignment: .topLeading) {
            if isOfflineReconnectUITest {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("offlineReconnect.debug.\(offlineReconnectUITestState)")
            }
        }
        .onChange(of: downloadManager.isOffline) { _, isOffline in
            if isOfflineReconnectUITest {
                offlineReconnectUITestState = isOffline ? "offline" : "online"
            }
            guard !isOffline else { return }
            guard sessionManager.status != .hydrating else { return }
            Task {
                guard !downloadManager.isOffline else { return }
                await sessionManager.hydrate()
                if sessionManager.status != .ready {
                    downloadManager.markOfflineDueToConnectionFailure()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            guard !isOfflineReconnectUITest else { return }
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
                if isOfflineReconnectUITest {
                    OfflineReconnectUITestOnlineView()
                } else {
                    RootTabView()
                        .id(sessionManager.plexServer?.clientIdentifier ?? "no-server")
                }
            }
        }
    }
}

private struct OfflineReconnectUITestOnlineView: View {
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            Text("Online")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
        .accessibilityIdentifier(OfflineReconnectUITestFixtures.onlineStateAccessibilityID)
    }
}
