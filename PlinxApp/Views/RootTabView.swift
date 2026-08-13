import SwiftUI
import PlinxCore
import PlinxUI

struct RootTabView: View {
    struct QuickActionOption: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let role: ButtonRole?
        let action: () -> Void
    }

    @Environment(SessionManager.self) var sessionManager
    @Environment(PlexAPIContext.self) var plexApiContext
    @Environment(SettingsManager.self) var settingsManager
    @Environment(LibraryStore.self) var libraryStore
    @Environment(DownloadManager.self) var downloadManager
    @Environment(ParentalAccessCoordinator.self) var parentalAccessCoordinator
    @Environment(DownloadOwnershipStore.self) var downloadOwnershipStore
    @Environment(SharePlayCoordinator.self) var sharePlayCoordinator
    @EnvironmentObject var mainCoordinator: MainCoordinator
    @EnvironmentObject var playbackLaunchCoordinator: PlaybackLaunchCoordinator
    @Environment(\.safetyPolicy) var safetyPolicy

    @State var showSettings = false
    @State var youtarrExploreConfiguration: YoutarrConfiguration?
    @State var isYoutarrConfigured = false
    @State var selectedQuickActionMedia: MediaDisplayItem?
    @State var quickActionErrorMessage: String?
    @State var homeViewModel: SafeHomeViewModel?
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
    @FocusState var focusedQuickActionID: String?
    #endif
    /// Local overrides for watched status, keyed by media item id.
    /// Updated instantly on toggle; cleared when home data reloads.
    @State var watchedOverrides: [String: Bool] = [:]
    @AppStorage(PlinxChromeButtonSizePreference.storageKey)
    var chromeButtonSizeRaw = PlinxChromeButtonSizePreference.defaultValue.rawValue
    @AppStorage(PlinxNavigationPreference.showSearchInMainNavigationStorageKey)
    var showSearchInMainNavigation = PlinxNavigationPreference.defaultShowSearchInMainNavigation
    @AppStorage(YoutarrExplorePreference.storageKey)
    var isYoutarrExploreEnabled = YoutarrExplorePreference.defaultEnabled
    @AppStorage(YoutarrConfigurationStore.baseURLKey)
    var youtarrStoredBaseURL = ""

    var chromeButtonSize: PlinxChromeButtonSizePreference {
        PlinxChromeButtonSizePreference(rawValue: chromeButtonSizeRaw) ?? .medium
    }

    var quickActionCornerRadius: CGFloat {
        #if os(tvOS)
        22
        #else
        14
        #endif
    }

    var quickActionOptionMinHeight: CGFloat {
        #if os(tvOS)
        78
        #else
        52
        #endif
    }

    var quickActionCancelMinHeight: CGFloat {
        #if os(tvOS)
        75
        #else
        50
        #endif
    }

    var quickActionIconSize: CGFloat {
        #if os(tvOS)
        24
        #else
        16
        #endif
    }

    var quickActionHorizontalPadding: CGFloat {
        #if os(tvOS)
        21
        #else
        14
        #endif
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

    var launcher: PlaybackLauncher {
        PlaybackLauncher(
            context: plexApiContext,
            coordinator: mainCoordinator,
            safetyPolicy: safetyPolicy
        )
    }

    var activeRootTab: MainCoordinator.Tab {
        switch mainCoordinator.tab {
        case .search:
            return .search
        case .library, .libraryDetail(_):
            return .library
        case .more:
            return .more
        case .seerrDiscover:
            return .seerrDiscover
        case .home:
            return .home
        }
    }

    var hasDownloadActivity: Bool {
        #if os(tvOS)
        false
        #else
        // CRITICAL: Check for ANY download items (queued, downloading, completed, failed)
        // NOT just completedItems. The downloads tab should show if there's any
        // download activity in progress, failed, or already completed.
        // See: Known regression where this checked only completedItems (commit 4357449)
        !downloadManager.items.isEmpty
        #endif
    }

    /// Tabs shown in the picker.
    var visibleTabs: [KidsMainTabPicker.TabItem] {
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
            .onAppear {
                sharePlayCoordinator.configurePlaybackLauncher(launcher)
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
            .onChange(of: settingsManager.interface.hiddenLibraryIds) { _, _ in
                mainCoordinator.resetToRoot(for: .library)
                Task {
                    await homeViewModel?.reload()
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
                if let item = selectedQuickActionMedia {
                    quickActionSheet(for: item)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: selectedQuickActionMedia != nil)
            .alert(
                Text("common.error.actionFailed", tableName: "Plinx"),
                isPresented: Binding(
                get: { quickActionErrorMessage != nil },
                set: { if !$0 { quickActionErrorMessage = nil } }
            )) {
                Button(
                    String(localized: "common.actions.ok", table: "Plinx"),
                    role: .cancel
                ) {}
            } message: {
                Text(quickActionErrorMessage ?? "")
            }
    }


}
