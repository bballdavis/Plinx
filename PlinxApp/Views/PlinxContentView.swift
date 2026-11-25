import Foundation
import PlinxCore
import PlinxUI
import SwiftUI

/// Root of the window: follows `SessionManager.status`, owns player
/// presentation, and keeps the offline, download and safety state of the
/// session in step with scene and network changes.
///
/// Launch rule: while an enrolled family connects, the screen shows Plinx
/// loading, never an offline warning. Offline content appears only once the
/// session is ready (cached content and the family's downloads), or, when the
/// session cannot be restored and the device has no network, as the offline
/// Downloads root of the profile pre-fork Plinx last signed in
/// (`PlinxLegacyOfflineSession`).
struct PlinxContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ServerRegistry.self) private var registry
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(ParentalAccessCoordinator.self) private var parentalAccessCoordinator
    @Environment(PlinxWatchStatusStore.self) private var watchStatusStore
    #if !os(tvOS)
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(OfflineCoordinator.self) private var offlineCoordinator
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var mainCoordinator: MainCoordinator
    @EnvironmentObject private var playbackLaunchCoordinator: PlaybackLaunchCoordinator
    @State private var pendingPlayerDetail: MediaItem?
    /// Content-policy revision the visible tab shell was built under.
    @State private var observedSafetyRevision: Int?
    /// Bumped when a new content policy is applied, which rebuilds the tab
    /// shell so every screen reloads through the updated safety boundary.
    @State private var safetyGeneration = 0
    /// Set once the pre-fork offline session snapshot has been deleted.
    @State private var retiredLegacyOfflineSession = false

    private struct PlaybackPresentationToken: Identifiable {
        let id = "plinx.playback.presentation"
    }

    /// Identity of the tab shell: a new profile activation (registry
    /// generation) or a newly applied content policy starts it fresh.
    private struct RootIdentity: Hashable {
        let registryGeneration: Int
        let safetyGeneration: Int
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
        .fullScreenCover(item: playbackPresentationBinding, onDismiss: consumePendingPlayerDetail) { _ in
            PlinxPlaybackPresentationView(onRequestMoreInfo: queuePlayerDetail)
                .environmentObject(playbackLaunchCoordinator)
                .environment(watchStatusStore)
        }
        .onAppear {
            applySafetyRevisionIfIdle()
            #if DEBUG
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                AppStoreScreenshotBootstrap.applyRequestedOrientation()
            }
            #endif
        }
        .onChange(of: registry.generation) { _, _ in
            // A new profile (or a new set of its servers) never inherits the
            // previous profile's pending navigation or optimistic state.
            pendingPlayerDetail = nil
            watchStatusStore.reset()
        }
        .onChange(of: mainCoordinator.isPresentingPlayer, initial: true) { _, isPresenting in
            sessionManager.isPlaybackActive = isPresenting
        }
        // ── Content policy ──────────────────────────────────────────
        .onChange(of: ContentSafetyGate.shared.revision) { _, _ in
            applySafetyRevisionIfIdle()
        }
        .onChange(of: parentalAccessCoordinator.isUnlocked) { _, _ in
            applySafetyRevisionIfIdle()
        }
        // ── Network and scene phase (as upstream's ContentView) ─────
        .onChange(of: registry.availability.hasNetworkPath) { _, hasNetworkPath in
            guard hasNetworkPath, sessionManager.status == .migrationFailed else { return }
            Task {
                await sessionManager.hydrate()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
        #if !os(tvOS)
        .onChange(of: settingsManager.downloads.offlineCacheLimitMB, initial: true) { _, megabytes in
            offlineCoordinator.setCacheLimit(megabytes: megabytes)
        }
        .onChange(of: registry.connectedServices.map(ObjectIdentifier.init), initial: true) { _, _ in
            activateDownloadOwners()
        }
        .onChange(of: isMigrationFailedOffline) { _, _ in
            activateDownloadOwners()
        }
        #endif
        .onChange(of: sessionManager.status, initial: true) { _, status in
            retireLegacyOfflineSessionIfUpdated(status)
        }
    }

    // MARK: - Session content

    @ViewBuilder
    private var sessionContent: some View {
        if showsStaticDownloads {
            offlineDownloadsRoot
        } else {
            switch sessionManager.status {
            case .hydrating:
                // Connecting is not being offline: no warning until the
                // session is ready or known to have failed.
                PlinxBrandedLoadingView(context: .appTransition)
            case .needsAccount:
                // Families add a Plex account or a Jellyfin server.
                AccountSetupView(purpose: .firstLaunch, sessionManager: sessionManager)
            case .needsProfileSelection:
                NavigationStack {
                    ProfileSwitcherView(viewModel: ProfileSwitcherViewModel(sessionManager: sessionManager))
                }
            case .migrationFailed:
                ZStack {
                    PlinxAmbientBackground(intensity: .hero)
                    PlinxConnectionRecoveryView()
                }
            case .ready:
                RootTabView(
                    homeViewModel: HomeViewModel(sessionManager: sessionManager, settingsManager: settingsManager)
                )
                .id(RootIdentity(registryGeneration: registry.generation, safetyGeneration: safetyGeneration))
            }
        }
    }

    /// Without a restorable session and without network, downloads are shown
    /// directly at launch (upstream's static downloads). Plinx limits this to a
    /// session that could not be restored (`migrationFailed`): with no account
    /// at all there is no profile that could own downloads, so onboarding
    /// stays in front. Only downloads of the active owners that the content
    /// policy allows count, never every profile's downloads on the device. In
    /// this state the only owner is the profile pre-fork Plinx last signed in
    /// (`activateDownloadOwners`); with no owner active the recovery card is
    /// shown alone (fail closed).
    private var showsStaticDownloads: Bool {
        #if os(tvOS)
        false
        #else
        guard isMigrationFailedOffline else {
            return false
        }
        return !DownloadAccessPolicy(downloadManager: downloadManager)
            .filter(downloadManager.ownedItems)
            .isEmpty
        #endif
    }

    #if !os(tvOS)
    /// The one-time update to accounts and profiles could not finish and the
    /// device has no network to retry it.
    private var isMigrationFailedOffline: Bool {
        sessionManager.status == .migrationFailed && !offlineCoordinator.availability.hasNetworkPath
    }

    /// Sets whose downloads the app lists and plays. Normally these are the
    /// owners of the connected services. While the update cannot finish
    /// offline there are no services yet, so the profile pre-fork Plinx last
    /// signed in, and only that profile, owns the offline Downloads root
    /// (`PlinxLegacyOfflineSession`). Leaving that state, for example when the
    /// network returns and the update is retried, hands ownership back to the
    /// connected services, which are none until a profile is active again.
    private func activateDownloadOwners() {
        let fallbackOwner = PlinxLegacyOfflineSession.fallbackOwner(
            status: sessionManager.status,
            hasNetworkPath: offlineCoordinator.availability.hasNetworkPath,
            snapshotOwner: { PlinxLegacyOfflineSession.snapshotOwner() }
        )
        if let fallbackOwner {
            downloadManager.activateOwners([fallbackOwner])
        } else {
            downloadManager.activateSession(services: registry.connectedServices)
        }
    }
    #endif

    /// Deletes the pre-fork offline session snapshot once the update to
    /// accounts and profiles has finished; it is never needed after that.
    private func retireLegacyOfflineSessionIfUpdated(_ status: SessionManager.Status) {
        guard !retiredLegacyOfflineSession,
              PlinxLegacyOfflineSession.updateHasFinished(status)
        else { return }
        retiredLegacyOfflineSession = true
        PlinxSignOut.removeLegacyOfflineAuthorization()
    }

    @ViewBuilder
    private var offlineDownloadsRoot: some View {
        #if !os(tvOS)
        ZStack(alignment: .bottom) {
            NavigationStack {
                PlinxDownloadsGridView()
                    .background(PlinxAmbientBackground(intensity: .restrained))
                    .toolbar(.hidden, for: .navigationBar)
            }
            PlinxConnectionRecoveryView(downloadsAvailable: true)
        }
        #endif
    }

    // MARK: - Scene phase

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            sessionManager.sceneWillReturnFromBackground()
            #if !os(tvOS)
            offlineCoordinator.availability.refresh()
            #endif
            registry.retryUnavailable()
        case .background:
            sessionManager.sceneDidEnterBackground()
            #if !os(tvOS)
            offlineCoordinator.evictCacheIfNeeded()
            #endif
        case .inactive:
            sessionManager.sceneWillReturnFromBackground()
        @unknown default:
            break
        }
    }

    // MARK: - Content policy

    /// Applies a new content policy by rebuilding the tab shell. While a parent
    /// is in protected settings (gate unlocked) the rebuild waits, so changing
    /// a rating ceiling never closes the settings being edited; relocking on
    /// close applies it. Pushed screens are popped because they may show an
    /// item the new policy no longer allows.
    private func applySafetyRevisionIfIdle() {
        let revision = ContentSafetyGate.shared.revision
        guard let observed = observedSafetyRevision else {
            observedSafetyRevision = revision
            return
        }
        guard revision != observed, !parentalAccessCoordinator.isUnlocked else { return }
        observedSafetyRevision = revision
        pendingPlayerDetail = nil
        mainCoordinator.resetAllToRoot()
        safetyGeneration &+= 1
    }

    // MARK: - Player presentation

    private var playbackPresentationBinding: Binding<PlaybackPresentationToken?> {
        Binding(
            get: {
                guard playbackLaunchCoordinator.pendingLaunch != nil
                    || mainCoordinator.isPresentingPlayer
                else {
                    return nil
                }
                return PlaybackPresentationToken()
            },
            set: { newValue in
                guard newValue == nil else { return }
                playbackLaunchCoordinator.cancelPendingLaunch()
                mainCoordinator.resetPlayer()
            }
        )
    }

    /// Player More Info intentionally crosses the full-screen presentation
    /// boundary only after dismissal. This avoids competing navigation updates
    /// and makes an ordinary player exit a no-op for root navigation.
    private func queuePlayerDetail(_ media: MediaItem) {
        guard ContentSafetyGate.shared.isAllowed(media) else { return }
        pendingPlayerDetail = media
    }

    private func consumePendingPlayerDetail() {
        guard let media = pendingPlayerDetail else { return }
        pendingPlayerDetail = nil
        guard ContentSafetyGate.shared.isAllowed(media) else { return }
        mainCoordinator.showMediaDetail(media)
    }

    // MARK: - Root

    /// The session's screens. Debug builds launched for UI tests or
    /// screenshots (`--ui-testing` with `PLINX_UI_TEST_SCREEN`) can open a
    /// fixture route instead; Release builds have no such routes.
    @ViewBuilder
    private var rootContent: some View {
        #if DEBUG
        if let uiTestScreenOverride {
            uiTestRoute(uiTestScreenOverride)
        } else {
            sessionContent
        }
        #else
        sessionContent
        #endif
    }
}

// MARK: - Pre-fork offline session

/// The profile pre-fork Plinx last signed in on this device, so a family that
/// opens the app offline right after the update keeps that profile's
/// downloads.
///
/// The one-time update to accounts and profiles (`MultiServerMigration`) needs
/// plex.tv to learn who the saved Plex sign-in belongs to. Offline it fails
/// (`SessionManager.Status.migrationFailed`), no profile is active, and no
/// download has an active owner. Pre-fork Plinx kept a Keychain snapshot of
/// its last ready session (`plinx.offlineSession.v1`: the Plex server's
/// machine identifier and the Plex Home user's UUID, never a token) and showed
/// that profile's downloads offline. Read here, that pair is the same Plex
/// `MediaOwner` its downloads were given (`LegacyDownloadOwnership`), so the
/// offline Downloads root lists exactly that profile's own downloads, still
/// checked by `DownloadAccessPolicy` and the content gate.
///
/// Fail closed: no snapshot, an unreadable one, or an empty identifier gives
/// no owner, and the recovery card is shown alone. The snapshot is read only
/// while the update cannot finish offline; once it finishes, the snapshot is
/// deleted (`updateHasFinished`), as Log Out deletes it.
@MainActor
enum PlinxLegacyOfflineSession {
    /// True once the update to accounts and profiles has finished, or was not
    /// needed: the session left loading for anything but the recovery state.
    static func updateHasFinished(_ status: SessionManager.Status) -> Bool {
        switch status {
        case .hydrating, .migrationFailed:
            false
        case .needsAccount, .needsProfileSelection, .ready:
            true
        }
    }

    #if !os(tvOS)
    /// The owner whose downloads the offline Downloads root may show, or `nil`
    /// when the connected services decide. Only while the update has failed
    /// and the device has no network; the snapshot is not read otherwise.
    static func fallbackOwner(
        status: SessionManager.Status,
        hasNetworkPath: Bool,
        snapshotOwner: () -> MediaOwner?
    ) -> MediaOwner? {
        guard status == .migrationFailed, !hasNetworkPath else { return nil }
        return snapshotOwner()
    }

    /// The owner recorded in this device's snapshot, or `nil`.
    static func snapshotOwner(
        secureStore: any SecureStore = Keychain(service: Bundle.main.bundleIdentifier ?? "com.bballdavis.plinx")
    ) -> MediaOwner? {
        guard let stored = try? secureStore.string(forKey: PlinxSignOut.legacyOfflineSessionKey) else {
            return nil
        }
        return owner(fromSnapshot: Data(stored.utf8))
    }

    /// Pre-fork Plinx only ever recorded Plex sessions.
    static func owner(fromSnapshot data: Data) -> MediaOwner? {
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        let serverIdentifier = snapshot.identity.serverIdentifier
        let profileIdentifier = snapshot.identity.profileIdentifier
        guard !serverIdentifier.isEmpty, !profileIdentifier.isEmpty else { return nil }
        return MediaOwner(
            server: ServerIdentity(provider: .plex, id: serverIdentifier),
            userID: profileIdentifier
        )
    }

    /// The part of pre-fork Plinx's `OfflineSessionSnapshot` that names the
    /// profile; its server and profile names and save date are not used.
    private struct Snapshot: Decodable {
        struct Identity: Decodable {
            let serverIdentifier: String
            let profileIdentifier: String
        }

        let identity: Identity
    }
    #endif
}

// MARK: - UI test routes (Debug only)

#if DEBUG
extension PlinxContentView {
    private var uiTestScreenOverride: String? {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else {
            return nil
        }
        return ProcessInfo.processInfo.environment["PLINX_UI_TEST_SCREEN"]
    }

    private var uiTestReduceMotion: Bool {
        ProcessInfo.processInfo.environment["PLINX_UI_TEST_REDUCE_MOTION"] == "1"
    }

    @ViewBuilder
    private func uiTestRoute(_ screen: String) -> some View {
        switch screen {
        case "parentalGate":
            ParentalGateUITestHarness()
        case "parentalPINGate":
            ParentalGateUITestHarness(pin: "2468")
        case "signIn":
            NavigationStack {
                SignInView(viewModel: SignInViewModel(onToken: { token in
                    _ = try await sessionManager.addPlexAccount(token: token)
                    await sessionManager.finishFirstLaunch()
                }))
            }
        case "accountSetup":
            AccountSetupView(purpose: .firstLaunch, sessionManager: sessionManager)
        case "playerSettings":
            playerSettingsPreview
        case "playerTimeline":
            PlayerTimelineUITestHarness()
        case "loadingGallery":
            loadingGalleryPreview
        case "homeLoading":
            homeLoadingPreview
        case "appHydrating":
            appHydratingPreview
        case "contentLoading":
            contentLoadingPreview
        case "homeHeader":
            homeHeaderPreview
        case "playerBuffering":
            playerBufferingPreview
        case "playerLoading":
            PlinxPlaybackLoadingView(onExit: {})
        case "refreshLoading":
            refreshLoadingPreview
        case "settings":
            #if os(tvOS)
            AppleTVSettingsNavigationUITestHarness()
            #else
            NavigationStack {
                PlinxSettingsView(isUnlocked: true)
            }
            #endif
        #if os(tvOS)
        case "settingsNavigation":
            AppleTVSettingsNavigationUITestHarness()
        case "appleTVBrowseFocus":
            AppleTVBrowseFocusUITestHarness(
                scenario: .root(hasContent: true),
                reduceMotion: uiTestReduceMotion
            )
        case "appleTVBrowseFocusEmpty":
            AppleTVBrowseFocusUITestHarness(scenario: .root(hasContent: false))
        case "appleTVLibraryDetailFocus":
            AppleTVBrowseFocusUITestHarness(scenario: .libraryDetail(hasContent: true))
        case "appleTVSearchFocus":
            AppleTVBrowseFocusUITestHarness(scenario: .search)
        case "profileSwitcherModal":
            AppleTVProfileSwitcherUITestHarness(sessionManager: sessionManager, modal: true)
        case "playerControls":
            AppleTVPlayerControlsUITestHarness()
        case "playerTracks":
            AppleTVPlayerTracksUITestHarness()
        case "quickActions":
            AppleTVQuickActionUITestHarness()
        case "libraryLoading":
            AppleTVLibraryLoadingUITestHarness()
        #endif
        case AppStoreScreenshotBootstrap.mediaDetailScreen:
            AppStoreMediaDetailScreenshotHarness()
        case "profileSwitcher":
            NavigationStack {
                #if os(tvOS)
                AppleTVProfileSwitcherUITestHarness(sessionManager: sessionManager, modal: false)
                #else
                ProfileSwitcherView(viewModel: ProfileSwitcherViewModel(sessionManager: sessionManager))
                #endif
            }
        case "selectServer":
            NavigationStack {
                SelectServerView(
                    viewModel: ServerSelectionViewModel(
                        loadServers: { try await uiTestPlexServers() },
                        onContinue: { _ in }
                    )
                )
            }
        case YoutarrLiveTestBootstrap.screenName:
            if let configuration = YoutarrLiveTestBootstrap.configuration() {
                NavigationStack {
                    YoutarrExploreView(
                        configuration: configuration,
                        safetyPolicy: YoutarrLiveTestBootstrap.safetyPolicy()
                    )
                }
            } else {
                ContentUnavailableView(
                    "Live test configuration missing",
                    systemImage: "wrench.and.screwdriver"
                )
            }
        case YoutarrExploreUITestBootstrap.screenName:
            if let configuration = YoutarrExploreUITestBootstrap.configuration() {
                YoutarrExploreUITestHarness(
                    configuration: configuration
                )
            } else {
                ContentUnavailableView(
                    "Synthetic Explore configuration missing",
                    systemImage: "wrench.and.screwdriver"
                )
            }
        #if !os(tvOS)
        case DownloadUITestFixtures.screenName:
            DownloadUITestHarness()
        case "seasonDownloadOffline":
            SeasonDownloadUITestHarness()
        case "demoPlayer":
            demoPlayerPreview
        #endif
        default:
            sessionContent
        }
    }

    /// Servers of the first Plex account, for the server-selection route.
    private func uiTestPlexServers() async throws -> [PlexCloudResource] {
        guard let account = sessionManager.accountStore.plexAccounts.first else { return [] }
        return try await sessionManager.plexServers(
            accountID: MediaAccount.plexID(account.id),
            userUUID: account.id
        )
    }

    /// Player settings now live inside the player and depend on a running
    /// playback session; the standalone preview only shows a placeholder.
    private var playerSettingsPreview: some View {
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
        PlinxBrandedLoadingView(context: .appTransition)
    }

    #if os(iOS)
    /// Launch the real local demo player directly for focused playback UI
    /// checks, without making those checks depend on onboarding navigation.
    private var demoPlayerPreview: some View {
        PlinxBrandedLoadingView(context: .appTransition)
            .task {
                while sessionManager.status == .hydrating {
                    try? await Task.sleep(for: .milliseconds(25))
                    guard !Task.isCancelled else { return }
                }
                await DemoFixtureBootstrap.start(sessionManager: sessionManager)
                guard DemoFixtureBootstrap.isActive,
                      sessionManager.status == .ready,
                      let demoServer = registry.sessions.first(where: {
                          $0.identity.id == DemoFixtureBootstrap.serverIdentifier
                      }),
                      let services = registry.services(for: demoServer.identity)
                else { return }
                let launcher = PlaybackLauncher(
                    services: services,
                    coordinator: mainCoordinator,
                    gate: ContentSafetyGate(policy: .ratingOnly(maxMovie: .pg, maxTV: .tvPg, allowUnrated: false))
                )
                _ = await launcher.play(ratingKey: "moonbound", type: .movie, shouldResumeFromOffset: false)
            }
    }
    #endif

    private var appHydratingPreview: some View {
        PlinxBrandedLoadingView(context: .appTransition)
    }

    private var contentLoadingPreview: some View {
        PlinxBrandedLoadingView(
            context: .content,
            titleKey: LocalizedStringResource(
                "library.loading.plinx",
                table: "Plinx"
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
    }

    private var homeHeaderPreview: some View {
        #if os(tvOS)
        return AnyView(Color.appBackground.ignoresSafeArea())
        #else
        return AnyView(
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    PlinxScrollingHeaderRow(
                        title: "tabs.home",
                        showsSettingsButton: true,
                        showsSearchButton: true,
                        showsLogo: true,
                        chromeButtonSize: .medium,
                        onSearch: {},
                        onSettings: {}
                    )

                    Text("Continue Watching")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("home.header.preview.firstSection")
                }
                .padding(.top, 8)
            }
            .background(Color.appBackground.ignoresSafeArea())
        )
        #endif
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
}

private struct ParentalGateUITestHarness: View {
    @State private var isAllowed = false
    @State private var parentalAccessCoordinator: ParentalAccessCoordinator
    #if os(tvOS)
    @State private var selectedTab: MainCoordinator.Tab = .home
    @State private var contentFocusRequest = 0
    @State private var shellFocusHistory: [String] = []
    @FocusState private var focusedShellTarget: PlinxTVShellFocusTarget?
    #endif

    init(pin: String? = nil) {
        let suiteName = "com.bballdavis.plinx.ui-tests.parental-gate"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        _parentalAccessCoordinator = State(
            initialValue: ParentalAccessCoordinator(
                store: FixtureParentalPINStore(pin: pin),
                legacyDefaults: defaults
            )
        )
    }

    var body: some View {
        #if os(tvOS)
        tvContent
            .environment(parentalAccessCoordinator)
        #else
        Group {
            if isAllowed {
                EmptyView()
            } else {
                ParentalGateView {
                    isAllowed = true
                }
            }
        }
        .environment(parentalAccessCoordinator)
        #endif
    }

    #if os(tvOS)
    private var tvContent: some View {
        ZStack(alignment: .top) {
            if isAllowed {
                NavigationStack {
                    PlinxSettingsView(
                        isUnlocked: true,
                        contentFocusRequest: contentFocusRequest,
                        onRequestShellNavigationFocus: {
                            focusedShellTarget = .settings
                        }
                    )
                }
            } else {
                ParentalGateView(
                    onAllowed: {
                        isAllowed = true
                    },
                    onRequestShellNavigationFocus: {
                        focusedShellTarget = .settings
                    },
                    contentFocusRequest: contentFocusRequest
                )
            }

            PlinxTVShellHeader(
                tabs: KidsMainTabPicker.TabItem.mainTabs(
                    showSearchInMainNavigation: true,
                    includeSettings: true
                ),
                selectedTab: $selectedTab,
                selectedAction: .settings,
                leadingIdentity: .title("Settings"),
                focusedTarget: $focusedShellTarget,
                onSelect: { destination in
                    selectedTab = destination
                    focusedShellTarget = .tab(destination)
                },
                onAction: { _ in
                    focusedShellTarget = .settings
                },
                onMoveDown: {
                    contentFocusRequest &+= 1
                },
                appearance: isAllowed ? .standard : .onBrightBrandSurface
            )

            Text(shellFocusHistory.joined(separator: ","))
                .font(.system(size: 1))
                .opacity(0.001)
                .accessibilityIdentifier("focus.fixture.shellHistory")
                .accessibilityValue(shellFocusHistory.joined(separator: ","))
        }
        .onChange(of: focusedShellTarget) { _, target in
            guard let target else { return }
            switch target {
            case let .tab(tab):
                switch tab {
                case .home:
                    shellFocusHistory.append("home")
                case .library, .libraryDetail:
                    shellFocusHistory.append("library")
                case .search:
                    shellFocusHistory.append("search")
                case .more, .downloads:
                    shellFocusHistory.append("more")
                case .seerrDiscover:
                    shellFocusHistory.append("explore")
                case .favorites, .liveTV:
                    shellFocusHistory.append("other")
                }
            case .settings:
                shellFocusHistory.append("settings")
            }
        }
    }
    #endif
}

private struct FixtureParentalPINStore: ParentalPINStoring {
    let pin: String?
    func readPIN() throws -> String? {
        pin
    }

    func writePIN(_: String) throws {}
    func deletePIN() throws {}
}
#endif
