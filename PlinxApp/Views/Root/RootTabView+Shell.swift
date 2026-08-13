import SwiftUI
import PlinxCore
import PlinxUI

extension RootTabView {
    @ViewBuilder
    var mainTabView: some View {
        let content = tabContainer
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .tabBar)
            .environment(\.watchedOverrides, watchedOverrides)
            #if os(tvOS)
            .environment(mediaFocusModel)
            .environmentObject(tvFocusCoordinator)
            #endif

        #if os(tvOS)
        ZStack(alignment: .top) {
            if showSettings {
                tvOSSettingsContent
            } else {
                content
            }

            tvOSShellHeader
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PlinxAmbientBackground(intensity: .restrained))
        #else
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                KidsMainTabPicker(
                    tabs: visibleTabs,
                    selectedTab: tabBinding,
                    onSelect: handleTabSelection,
                    onAction: handleBottomAction
                )
            }
        #endif
    }

    @ViewBuilder
    var tabContainer: some View {
        #if os(tvOS)
        tabStack(for: activeRootTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        ZStack {
            tabStack(for: .home)
            tabStack(for: .search)
            tabStack(for: .more)
            tabStack(for: .library)
            tabStack(for: .seerrDiscover)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showSettings) {
            Group {
                if parentalAccessCoordinator.isUnlocked {
                    NavigationStack {
                        PlinxSettingsView()
                            .toolbar(.hidden, for: .navigationBar)
                            .safeAreaInset(edge: .top, spacing: 0) {
                                settingsHeaderRow
                            }
                    }
                } else {
                    ParentalGateView {
                        // The coordinator owns the authorization state. This
                        // closure exists so UI-test and future presentation
                        // layers can react without bypassing that state.
                    }
                }
            }
            .presentationDetents([.large])
        }
        #endif
    }

    #if os(tvOS)
    var tvOSShellHeader: some View {
        PlinxTVShellHeader(
            tabs: visibleTabs,
            selectedTab: tabBinding,
            selectedAction: showSettings ? .settings : nil,
            leadingIdentity: PlinxTVShellLeadingIdentity.resolve(
                showsSettings: showSettings,
                activeTab: activeRootTab,
                libraryTitle: mainCoordinator.libraryPath.isEmpty ? nil : tvLibraryShellTitle
            ),
            focusedTarget: $focusedShellTarget,
            onSelect: handleTabSelection,
            onAction: handleBottomAction,
            onMoveDown: requestFirstContentFocus,
            appearance: showSettings && !parentalAccessCoordinator.isUnlocked
                ? .onBrightBrandSurface
                : .standard
        )
    }

    @ViewBuilder
    var tvOSSettingsContent: some View {
        Group {
            if parentalAccessCoordinator.isUnlocked {
                NavigationStack {
                    PlinxSettingsView(
                        contentFocusRequest: settingsContentFocusRequest,
                        onRequestShellNavigationFocus: {
                            focusedShellTarget = .settings
                        }
                    )
                        .toolbar(.hidden, for: .navigationBar)
                        .safeAreaInset(edge: .top, spacing: 0) {
                            settingsHeaderRow
                        }
                }
            } else {
                ParentalGateView(
                    onAllowed: {
                        tvFocusCoordinator.activate(.settings)
                        settingsContentFocusRequest &+= 1
                    },
                    onRequestShellNavigationFocus: {
                        focusedShellTarget = .settings
                    },
                    contentFocusRequest: settingsContentFocusRequest
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .environment(\.plinxSettingsNavigationCoordinator, settingsNavigationCoordinator)
        .onExitCommand {
            guard !settingsNavigationCoordinator.dismissTopDestination() else { return }
            closeSettings()
        }
    }
    #endif

    @ViewBuilder
    func tabStack(for tab: MainCoordinator.Tab) -> some View {
        switch tab {
        case .home:
            let viewModel = homeViewModel ?? SafeHomeViewModel(
                context: plexApiContext,
                settingsManager: settingsManager,
                libraryStore: libraryStore,
                policy: safetyPolicy
            )

            NavigationStack(path: mainCoordinator.pathBinding(for: .home)) {
                PlinxHomeView(
                    viewModel: viewModel,
                    topContent: scrollingHeaderContent(
                        title: "tabs.home",
                        showsSettingsButton: true,
                        showsSearchButton: !showSearchInMainNavigation,
                        showsLogo: true
                    ),
                    onSelectMedia: { displayItem in
                        handlePrimarySelection(displayItem)
                    },
                    onLongPressMedia: { displayItem in
                        selectedQuickActionMedia = displayItem
                    },
                    onRequestHomeNavigationFocus: {
                        requestHeaderFocus()
                    },
                    contentFocusRequest: homeContentFocusRequest,
                    isItemWatched: { displayItem in
                        isWatchedDisplay(displayItem)
                    }
                )
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: MainCoordinator.Route.self) { route in
                    destination(for: route)
                }
            }
            .opacity(activeRootTab == .home ? 1 : 0)
            .allowsHitTesting(activeRootTab == .home)
            .accessibilityHidden(activeRootTab != .home)
            .onAppear {
                if homeViewModel == nil {
                    homeViewModel = viewModel
                }
                #if os(tvOS)
                tvFocusCoordinator.activate(.home)
                #endif
            }

        case .search:
            NavigationStack(path: mainCoordinator.pathBinding(for: .search)) {
                PlinxSearchView(
                    viewModel: SafeSearchViewModel(
                        inner: SearchViewModel(
                            context: plexApiContext,
                            settingsManager: settingsManager,
                            libraryStore: libraryStore
                        ),
                        policy: safetyPolicy
                    ),
                    topContent: scrollingHeaderContent(title: "tabs.search", showsSettingsButton: false),
                    onRequestShellNavigationFocus: {
                        requestHeaderFocus()
                    },
                    contentFocusRequest: searchContentFocusRequest,
                    onSelectMedia: { displayItem in
                        handlePrimarySelection(displayItem)
                    },
                    onLongPressMedia: { displayItem in
                        selectedQuickActionMedia = displayItem
                    }
                )
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: MainCoordinator.Route.self) { route in
                    destination(for: route)
                }
            }
            .opacity(activeRootTab == .search ? 1 : 0)
            .allowsHitTesting(activeRootTab == .search)
            .accessibilityHidden(activeRootTab != .search)
            #if os(tvOS)
            .onAppear {
                tvFocusCoordinator.activate(.search)
            }
            #endif

        case .library:
            NavigationStack(path: mainCoordinator.pathBinding(for: .library)) {
                PlinxLibraryView(
                    viewModel: SafeLibraryViewModel(
                        inner: LibraryViewModel(
                            context: plexApiContext,
                            libraryStore: libraryStore
                        ),
                        policy: safetyPolicy,
                        hiddenLibraryIDs: Set(settingsManager.interface.hiddenLibraryIds),
                        context: plexApiContext
                    ),
                    topContent: scrollingHeaderContent(title: "tabs.library".plinxLocalized, showsSettingsButton: false),
                    onSelectLibrary: { library in
                        #if os(tvOS)
                        tvLibraryShellTitle = library.title
                        #endif
                        mainCoordinator.libraryPath.append(library)
                    },
                    onRequestShellNavigationFocus: {
                        requestHeaderFocus()
                    },
                    contentFocusRequest: libraryContentFocusRequest
                )
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Library.self) { library in
                    PlinxLibraryDetailView(
                        library: library,
                        onSelectMedia: { displayItem in
                            handlePrimarySelection(displayItem)
                        },
                        onLongPressMedia: { displayItem in
                            selectedQuickActionMedia = displayItem
                        },
                        onRequestShellNavigationFocus: {
                            requestHeaderFocus()
                        },
                        contentFocusRequest: libraryDetailContentFocusRequest
                    )
                    #if os(tvOS)
                    .onAppear {
                        tvLibraryShellTitle = library.title
                    }
                    #endif
                }
                .navigationDestination(for: MainCoordinator.Route.self) { route in
                    destination(for: route)
                }
            }
            .opacity(activeRootTab == .library ? 1 : 0)
            .allowsHitTesting(activeRootTab == .library)
            .accessibilityHidden(activeRootTab != .library)
            #if os(tvOS)
            .onAppear {
                tvFocusCoordinator.activate(.library)
            }
            #endif

        case .more:
            NavigationStack(path: mainCoordinator.pathBinding(for: .more)) {
                #if os(tvOS)
                EmptyView()
                    .onAppear {
                        mainCoordinator.resetToRoot(for: .home)
                        mainCoordinator.tab = .home
                    }
                #else
                PlinxDownloadsGridView()
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: MainCoordinator.Route.self) { route in
                        destination(for: route)
                    }
                #endif
            }
            .opacity(activeRootTab == .more ? 1 : 0)
            .allowsHitTesting(activeRootTab == .more)
            .accessibilityHidden(activeRootTab != .more)

        case .seerrDiscover:
            if let configuration = youtarrExploreConfiguration {
                NavigationStack(
                    path: mainCoordinator.pathBinding(for: .seerrDiscover)
                ) {
                    YoutarrExploreTabContent(
                        configuration: configuration,
                        safetyPolicy: safetyPolicy,
                        isActive: activeRootTab == .seerrDiscover,
                        onRequestShellNavigationFocus: {
                            requestHeaderFocus()
                        },
                        contentFocusRequest: exploreContentFocusRequest
                    )
                }
                .id(youtarrStoredBaseURL)
                .opacity(activeRootTab == .seerrDiscover ? 1 : 0)
                .allowsHitTesting(activeRootTab == .seerrDiscover)
                .accessibilityHidden(activeRootTab != .seerrDiscover)
            }

        case .libraryDetail(_):
            EmptyView()
        }
    }

    func handleTabSelection(_ newValue: MainCoordinator.Tab) {
        let decision = RootTabSelectionPolicy.decision(
            isSettingsPresented: showSettings,
            currentTab: activeRootTab,
            selectedTab: newValue
        )

        #if os(tvOS)
        if decision.closesSettings {
            settingsExitDestination = decision.destination
            tvFocusCoordinator.activate(contentRegion(for: decision.destination))
            focusedShellTarget = .tab(decision.destination)
            showSettings = false
            mainCoordinator.tab = decision.destination
            return
        }

        // Update focus ownership synchronously. Waiting for the tab view's
        // onChange callback leaves a small window where Down can still be
        // routed to the previously visible Library region.
        tvFocusCoordinator.activate(contentRegion(for: decision.destination))
        focusedShellTarget = .tab(decision.destination)
        #endif

        if decision.resetsNavigationStack {
            mainCoordinator.resetToRoot(for: decision.destination)
        }
        mainCoordinator.tab = decision.destination
    }

    func handleBottomAction(_ action: KidsMainTabPicker.TabItem.Action) {
        switch action {
        case .settings:
            guard !showSettings else { return }
            #if os(tvOS)
            settingsExitDestination = nil
            #endif
            parentalAccessCoordinator.lock()
            showSettings = true
        }
    }

    func closeSettings() {
        showSettings = false
    }

    func normalizedRootTab(_ tab: MainCoordinator.Tab) -> MainCoordinator.Tab {
        if case .libraryDetail = tab { return .library }
        return tab
    }

    #if os(tvOS)
    func contentRegion(for tab: MainCoordinator.Tab) -> PlinxTVContentRegion {
        switch tab {
        case .home:
            .home
        case .search:
            .search
        case .library, .libraryDetail:
            .library
        case .more, .seerrDiscover:
            .other
        }
    }

    var visibleContentRegion: PlinxTVContentRegion {
        if activeRootTab == .library, !mainCoordinator.libraryPath.isEmpty {
            return .libraryDetail
        }
        return contentRegion(for: activeRootTab)
    }
    #endif

    func requestHeaderFocus() {
        #if os(tvOS)
        let normalizedTab = normalizedRootTab(activeRootTab)
        let destination = HeaderFocusOrder.returnTarget(
            currentTab: normalizedTab,
            visibleTabs: visibleTabs
        ) ?? normalizedTab
        focusedShellTarget = .tab(destination)
        #endif
    }

    func requestFirstContentFocus() {
        #if os(tvOS)
        tvFocusCoordinator.requestContentFocus()
        switch tvFocusCoordinator.activeContentRegion {
        case .home:
            homeContentFocusRequest &+= 1
        case .search:
            searchContentFocusRequest &+= 1
        case .library:
            libraryContentFocusRequest &+= 1
        case .libraryDetail:
            libraryDetailContentFocusRequest &+= 1
        case .detail:
            detailContentFocusRequest &+= 1
        case .settings:
            settingsContentFocusRequest &+= 1
        case .other:
            exploreContentFocusRequest &+= 1
        }
        #endif
    }

    var settingsHeaderRow: some View {
        #if os(tvOS)
        Color.clear
            .frame(height: PlinxTVShellMetrics.contentClearance + 12)
            .accessibilityHidden(true)
        #else
        HStack(spacing: 12) {
            Text("tabs.settings".plinxLocalized)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white.opacity(0.95))
            Spacer()
            PlinxChromeButton(systemImage: "xmark") {
                closeSettings()
            }
            .accessibilityIdentifier("settings.close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        #endif
    }

    func scrollingHeaderContent(
        title: String,
        showsSettingsButton: Bool,
        showsSearchButton: Bool = false,
        showsLogo: Bool = false
    ) -> AnyView? {
        #if os(tvOS)
        AnyView(
            Color.clear
                .frame(height: PlinxTVShellMetrics.contentClearance)
                .accessibilityHidden(true)
        )
        #else
        AnyView(
            topTitleRow(
                title: title,
                showsSettingsButton: showsSettingsButton,
                showsSearchButton: showsSearchButton,
                showsLogo: showsLogo
            )
        )
        #endif
    }

    #if !os(tvOS)
    func topTitleRow(
        title: String,
        showsSettingsButton: Bool,
        showsSearchButton: Bool = false,
        showsLogo: Bool = false
    ) -> some View {
        PlinxScrollingHeaderRow(
            title: title,
            showsSettingsButton: showsSettingsButton,
            showsSearchButton: showsSearchButton,
            showsLogo: showsLogo,
            chromeButtonSize: chromeButtonSize,
            onSearch: { handleTabSelection(.search) },
            onSettings: {
                parentalAccessCoordinator.lock()
                showSettings = true
            }
        )
    }
    #endif

    func refreshYoutarrConfigurationState() {
        if let testConfiguration = YoutarrLiveTestBootstrap.mainTabConfiguration() {
            isYoutarrConfigured = true
            youtarrExploreConfiguration = testConfiguration
            return
        }
        let store = YoutarrConfigurationStore()
        let configuration = try? store.load()
        isYoutarrConfigured = configuration != nil
        youtarrExploreConfiguration = configuration
        if !YoutarrExploreVisibility.shouldShow(
            isEnabled: isYoutarrExploreEnabled,
            isConfigured: isYoutarrConfigured
        ) {
            if activeRootTab == .seerrDiscover {
                mainCoordinator.resetToRoot(for: .seerrDiscover)
                mainCoordinator.tab = .home
            }
        }
    }


}
