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
    @State private var reconnectTask: Task<Void, Never>?
    @State private var offlineReconnectUITestState = "offline"

    private enum ReconnectTrigger {
        case manual
        case foreground
        case connectionError
    }

    private var uiTestScreenOverride: String? {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else {
            return nil
        }
        return ProcessInfo.processInfo.environment["PLINX_UI_TEST_SCREEN"]
    }

    private var isOfflineReconnectUITest: Bool {
        uiTestScreenOverride == OfflineReconnectUITestFixtures.screenName
    }

    private var isLiveOfflineReconnectUITest: Bool {
        uiTestScreenOverride == LivePlexUITestBootstrap.offlineReconnectScreenName
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
            } else if isLiveOfflineReconnectUITest {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier(
                        "liveOfflineReconnect.debug.\(downloadManager.isOffline ? "offline" : "online").\(sessionStatusLabel(sessionManager.status))"
                    )
            }
        }
        .overlay(alignment: .topTrailing) {
            if isLiveOfflineReconnectUITest,
               !downloadManager.isOffline,
               sessionManager.status == .ready {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("liveOfflineReconnect.state.online")
            }
        }
        .onChange(of: downloadManager.isOffline) { _, isOffline in
            if isOfflineReconnectUITest {
                offlineReconnectUITestState = isOffline ? "offline" : "online"
            }
            // Mirror Strimr's ContentView pattern: when the OS path clears
            // isOffline automatically (via pathUpdateHandler), trigger session
            // hydration so the app transitions to online content seamlessly.
            guard !isOffline else { return }
            guard !isOfflineReconnectUITest, !isLiveOfflineReconnectUITest else { return }
            Task {
                await performReconnect(trigger: .foreground)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            guard !isOfflineReconnectUITest else { return }
            guard !isLiveOfflineReconnectUITest else { return }
            Task {
                await performReconnect(trigger: .foreground)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .plexConnectionUnavailable)) { _ in
            guard sessionManager.status != .hydrating else { return }
            Task {
                await performReconnect(trigger: .connectionError)
            }
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

    /// Re-hydrates the Plex session when the app comes online or a connection
    /// error fires. isOffline is now owned entirely by NWPathMonitor's
    /// pathUpdateHandler — no retry loop or recheckNetworkStatus call needed.
    @MainActor
    private func performReconnect(trigger: ReconnectTrigger) async {
        if let reconnectTask {
            await reconnectTask.value
            return
        }

        let task = Task { @MainActor in
            defer { reconnectTask = nil }
            _ = await reconnectProbe(for: trigger)
        }
        reconnectTask = task
        await task.value
    }

    @MainActor
    private func reconnectProbe(for trigger: ReconnectTrigger) async -> Bool {
        if isOfflineReconnectUITest {
            // Clear isOffline in the fixture (path monitor is suppressed in
            // tests so pathUpdateHandler never fires — recheckNetworkStatus
            // is the only way to flip isOffline = false in this path).
            await downloadManager.recheckNetworkStatus()
            await sessionManager.hydrate()
            return sessionManager.status != .hydrating
        }

        guard await plexApiContext.canReachServer() else {
            return false
        }

        switch trigger {
        case .manual, .foreground:
            guard sessionManager.status != .ready else {
                return true
            }
        case .connectionError:
            break
        }

        await sessionManager.hydrate()
        return sessionManager.status != .hydrating
    }

    private func sessionStatusLabel(_ status: SessionManager.Status) -> String {
        switch status {
        case .hydrating:
            return "hydrating"
        case .signedOut:
            return "signedOut"
        case .needsProfileSelection:
            return "needsProfileSelection"
        case .needsServerSelection:
            return "needsServerSelection"
        case .ready:
            return "ready"
        }
    }

    @ViewBuilder
    private var sessionContent: some View {
        if downloadManager.isOffline {
            OfflineRootView(onReconnectRequested: {
                await performReconnect(trigger: .manual)
            })
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
