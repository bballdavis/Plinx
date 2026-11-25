import PlinxCore
import PlinxUI
import SwiftUI

/// The kid-facing tab shell of a ready session: Home, Library, Search,
/// Downloads (iOS) and Explore (Youtarr), with protected Settings behind the
/// parental gate. Every screen reads its server's services from
/// `ServerRegistry`; content was already filtered by the safety boundary, and
/// `PlaybackLauncher` re-checks every playback.
///
/// `PlinxContentView` rebuilds this view for each profile activation and for
/// each newly applied content policy.
struct RootTabView: View {
    @Environment(SessionManager.self) var sessionManager
    @Environment(ServerRegistry.self) var registry
    @Environment(SettingsManager.self) var settingsManager
    @Environment(LibraryStore.self) var libraryStore
    #if !os(tvOS)
    @Environment(DownloadManager.self) var downloadManager
    @Environment(OfflineCoordinator.self) var offlineCoordinator
    #endif
    @Environment(ParentalAccessCoordinator.self) var parentalAccessCoordinator
    @Environment(SharePlayCoordinator.self) var sharePlayCoordinator
    @Environment(PlinxWatchStatusStore.self) var watchStatusStore
    @EnvironmentObject var mainCoordinator: MainCoordinator
    @EnvironmentObject var playbackLaunchCoordinator: PlaybackLaunchCoordinator
    @Environment(\.safetyPolicy) var safetyPolicy

    @State var homeViewModel: HomeViewModel
    /// Server of the item in the player, kept past `resetPlayer()` (which
    /// clears the player's services before the cover is dismissed) so closing
    /// the player can reload that server's home.
    @State var playedServer: ServerIdentity?
    @State var showSettings = false
    @State var youtarrExploreConfiguration: YoutarrConfiguration?
    @State var isYoutarrConfigured = false
    @State var selectedQuickActionMedia: MediaDisplayItem?
    @State var quickActionShowsPrimary = true
    @State var quickActionErrorMessage: String?
    @State var homeContentFocusRequest = 0
    @State var libraryContentFocusRequest = 0
    @State var searchContentFocusRequest = 0
    @State var libraryDetailContentFocusRequest = 0
    @State var detailContentFocusRequest = 0
    @State var settingsContentFocusRequest = 0
    @State var exploreContentFocusRequest = 0
    #if os(tvOS)
    @State var mediaFocusModel = MediaFocusModel()
    @StateObject var tvFocusCoordinator = PlinxTVFocusCoordinator()
    @State var settingsNavigationCoordinator = PlinxSettingsNavigationCoordinator()
    @State var settingsExitDestination: MainCoordinator.Tab?
    @State var tvLibraryShellTitle: String?
    @FocusState var focusedShellTarget: PlinxTVShellFocusTarget?
    #endif
    @AppStorage(PlinxChromeButtonSizePreference.storageKey)
    var chromeButtonSizeRaw = PlinxChromeButtonSizePreference.defaultValue.rawValue
    @AppStorage(PlinxNavigationPreference.showSearchInMainNavigationStorageKey)
    var showSearchInMainNavigation = PlinxNavigationPreference.defaultShowSearchInMainNavigation
    @AppStorage(YoutarrExplorePreference.storageKey)
    var isYoutarrExploreEnabled = YoutarrExplorePreference.defaultEnabled
    @AppStorage(YoutarrConfigurationStore.baseURLKey)
    var youtarrStoredBaseURL = ""

    /// - Parameter homeViewModel: the active profile's home, created by the session root.
    init(homeViewModel: HomeViewModel) {
        _homeViewModel = State(initialValue: homeViewModel)
    }

    var chromeButtonSize: PlinxChromeButtonSizePreference {
        PlinxChromeButtonSizePreference(rawValue: chromeButtonSizeRaw) ?? .medium
    }

    var showsYoutarrExplore: Bool {
        if YoutarrLiveTestBootstrap.mainTabConfiguration() != nil {
            return true
        }
        return YoutarrExploreVisibility.shouldShow(
            isEnabled: isYoutarrExploreEnabled,
            isConfigured: isYoutarrConfigured
        )
    }

    /// The final playback check for an item of `services`' server.
    func launcher(for services: MediaServices) -> PlaybackLauncher {
        PlaybackLauncher(
            services: services,
            coordinator: mainCoordinator,
            safetyPolicy: safetyPolicy
        )
    }

    /// Plinx shows Home, Search, Library, Downloads (`more`) and Explore
    /// (`seerrDiscover`, Youtarr). Other `MainCoordinator.Tab` cases fall back
    /// to the nearest Plinx destination.
    var activeRootTab: MainCoordinator.Tab {
        switch mainCoordinator.tab {
        case .search:
            .search
        case .library, .libraryDetail:
            .library
        case .more, .downloads:
            .more
        case .seerrDiscover:
            .seerrDiscover
        case .home, .favorites, .liveTV:
            .home
        }
    }

    /// Hidden libraries of the active profile; changing them pops Library and refreshes Home.
    var hiddenLibraries: [LibraryIdentity] {
        settingsManager.libraryPreferences(profileID: sessionManager.activeProfile?.id ?? "").hiddenLibraries
    }

    var hasDownloadActivity: Bool {
        #if os(tvOS)
        false
        #else
        // Any of this profile's downloads (queued, downloading, completed or
        // failed) keeps the Downloads tab, not only completed ones; titles the
        // current content policy hides do not count.
        !DownloadAccessPolicy(downloadManager: downloadManager).filter(downloadManager.ownedItems).isEmpty
        #endif
    }

    /// Without a network path, the family's downloads become the whole shell.
    var showsOfflineDownloadsRoot: Bool {
        #if os(tvOS)
        false
        #else
        hasDownloadActivity
            && (!offlineCoordinator.availability.hasNetworkPath || offlineCoordinator.isFullyOffline)
        #endif
    }

    /// Apple TV has no downloads: when every server of the profile is
    /// unreachable (not while it is still connecting), the content tabs show
    /// the connection recovery card instead of empty rows. Explore (Youtarr,
    /// its own server) and Settings stay available.
    var showsServerRecoveryCard: Bool {
        #if os(tvOS)
        let enabled = registry.enabledSessions
        return activeRootTab != .seerrDiscover
            && !enabled.isEmpty
            && !registry.isConnecting
            && enabled.allSatisfy { $0.status == .unreachable }
        #else
        false
        #endif
    }

    /// Tabs shown in the picker.
    var visibleTabs: [KidsMainTabPicker.TabItem] {
        if showsOfflineDownloadsRoot {
            return KidsMainTabPicker.TabItem.mainTabs(
                includeDownloads: true,
                showSearchInMainNavigation: false
            ).filter { $0.tab == .more }
        }
        #if os(tvOS)
        let showsSearch = true
        let includesSettings = true
        let includeDownloads = false
        #else
        let showsSearch = showSearchInMainNavigation
        let includesSettings = false
        let includeDownloads = hasDownloadActivity
        #endif

        return KidsMainTabPicker.TabItem.mainTabs(
            includeDownloads: includeDownloads,
            showSearchInMainNavigation: showsSearch,
            includeExplore: showsYoutarrExplore,
            includeSettings: includesSettings
        )
    }

    /// Maps coordinator tab to tab-bar selection.
    var tabBinding: Binding<MainCoordinator.Tab> {
        Binding(
            get: { activeRootTab },
            set: { newValue in
                handleTabSelection(newValue)
            }
        )
    }

    var body: some View {
        mainTabView
            .task {
                // Incoming SharePlay sessions present through the same
                // coordinator and go through PlaybackLauncher's checks.
                sharePlayCoordinator.configurePlaybackPresenter(mainCoordinator)
                try? await libraryStore.loadLibraries()
            }
            .task(id: registry.readyServers) {
                // Servers joining or leaving the profile update Home in place.
                await homeViewModel.syncServers()
            }
            .onChange(of: mainCoordinator.selectedMediaServices?.identity) { _, server in
                if let server {
                    playedServer = server
                }
            }
            .onChange(of: mainCoordinator.isPresentingPlayer, initial: true) { _, isPresenting in
                homeViewModel.isPlaybackActive = isPresenting
                guard !isPresenting, let server = playedServer else { return }
                // Closing the player reloads only the played
                // server's home, to update Continue Watching and Next Up.
                playedServer = nil
                Task { await homeViewModel.refresh(server: server) }
            }
            .onChange(of: mainCoordinator.tab, initial: true) { _, tab in
                // A saved startup screen (Favorites, Live TV, a pinned
                // library) is not a Plinx tab: navigate within the Plinx one.
                if tab != activeRootTab {
                    mainCoordinator.tab = activeRootTab
                }
            }
            .onChange(of: playbackLaunchCoordinator.lastResult) { _, result in
                guard let result else { return }
                handlePlaybackResult(result)
            }
        #if os(tvOS)
            .allowsHitTesting(selectedQuickActionMedia == nil)
        #endif
        #if os(tvOS)
            .onAppear {
            tvFocusCoordinator.activate(contentRegion(for: activeRootTab))
            focusedShellTarget = .tab(activeRootTab)
        }
        .onChange(of: activeRootTab) { _, newTab in
            tvFocusCoordinator.activate(contentRegion(for: newTab))
            focusedShellTarget = tvFocusCoordinator.shellTarget(
                activeTab: newTab,
                showsSettings: showSettings,
                visibleTabs: visibleTabs
            )
        }
        #endif
        .onChange(of: hasDownloadActivity) { _, hasDownloads in
            guard !hasDownloads, activeRootTab == .more else { return }
            mainCoordinator.resetToRoot(for: .more)
            mainCoordinator.tab = .home
        }
        .onChange(of: showSearchInMainNavigation) { _, isVisible in
            guard !isVisible, activeRootTab == .search else { return }
            mainCoordinator.resetToRoot(for: .home)
            mainCoordinator.tab = .home
        }
        .onChange(of: hiddenLibraries) { _, _ in
            mainCoordinator.resetToRoot(for: .library)
            Task {
                await homeViewModel.reload()
            }
        }
        .onChange(of: youtarrStoredBaseURL) { _, _ in
            refreshYoutarrConfigurationState()
        }
        .onChange(of: isYoutarrExploreEnabled) { _, _ in
            refreshYoutarrConfigurationState()
        }
        .task {
            refreshYoutarrConfigurationState()
        }
        .onChange(of: showSettings) { _, isPresented in
            if isPresented {
                #if os(tvOS)
                tvFocusCoordinator.beginModal(
                    from: tvFocusCoordinator.activeContentRegion,
                    shellTarget: focusedShellTarget ?? .tab(activeRootTab)
                )
                tvFocusCoordinator.activate(.settings)
                focusedShellTarget = .settings
                #endif
            } else {
                parentalAccessCoordinator.lock()
                refreshYoutarrConfigurationState()
                #if os(tvOS)
                let restoration = tvFocusCoordinator.endModal()
                if let destination = settingsExitDestination {
                    settingsExitDestination = nil
                    tvFocusCoordinator.activate(contentRegion(for: destination))
                    focusedShellTarget = .tab(destination)
                } else {
                    tvFocusCoordinator.activate(
                        restoration?.contentRegion ?? contentRegion(for: activeRootTab)
                    )
                    focusedShellTarget = restoration?.shellTarget ?? .tab(activeRootTab)
                }
                #endif
            }
        }
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                if let item = selectedQuickActionMedia {
                    quickActionSheet(for: item)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: selectedQuickActionMedia != nil)
        }
        .alert(
            Text("common.error.actionFailed", tableName: "Plinx"),
            isPresented: Binding(
                get: { quickActionErrorMessage != nil },
                set: {
                    if !$0 {
                        quickActionErrorMessage = nil
                    }
                }
            )
        ) {
            Button(
                String(localized: "common.actions.ok", table: "Plinx"),
                role: .cancel
            ) {}
        } message: {
            Text(quickActionErrorMessage ?? "")
        }
    }
}
