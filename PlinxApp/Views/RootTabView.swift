import SwiftUI
import PlinxCore
import PlinxUI

enum QuickActionFocusDirection {
    case up
    case down
}

enum QuickActionFocusOrder {
    static let cancelID = "cancel"

    static func focusIDs(optionIDs: [String]) -> [String] {
        optionIDs + [cancelID]
    }

    static func nextFocusedID(
        current: String?,
        optionIDs: [String],
        direction: QuickActionFocusDirection
    ) -> String? {
        let ids = focusIDs(optionIDs: optionIDs)
        guard !ids.isEmpty else { return nil }
        guard let current, let currentIndex = ids.firstIndex(of: current) else {
            return ids.first
        }

        switch direction {
        case .up:
            return ids[(currentIndex - 1 + ids.count) % ids.count]
        case .down:
            return ids[(currentIndex + 1) % ids.count]
        }
    }
}

enum HeaderFocusOrder {
    static func returnTarget(
        currentTab: MainCoordinator.Tab,
        visibleTabs: [KidsMainTabPicker.TabItem]
    ) -> MainCoordinator.Tab? {
        let tabs = visibleTabs.compactMap(\.tab)
        if tabs.contains(currentTab) {
            return currentTab
        }
        return tabs.first
    }
}

enum RootTabSelectionPolicy {
    struct Decision: Equatable {
        let destination: MainCoordinator.Tab
        let closesSettings: Bool
        let resetsNavigationStack: Bool
    }

    static func decision(
        isSettingsPresented: Bool,
        currentTab: MainCoordinator.Tab,
        selectedTab: MainCoordinator.Tab
    ) -> Decision {
        Decision(
            destination: selectedTab,
            closesSettings: isSettingsPresented,
            resetsNavigationStack: !isSettingsPresented && currentTab == selectedTab
        )
    }
}

#if os(tvOS)
enum PlinxTVShellLeadingIdentity: Equatable {
    case brand
    case title(String)

    static func resolve(
        showsSettings: Bool,
        activeTab: MainCoordinator.Tab,
        libraryTitle: String?
    ) -> Self {
        if showsSettings {
            return .title("tabs.settings".plinxLocalized)
        }

        switch activeTab {
        case .home:
            return .brand
        case .library, .libraryDetail:
            return .title(libraryTitle ?? "tabs.library".plinxLocalized)
        case .search:
            return .title("tabs.search".plinxLocalized)
        case .more:
            return .title("tabs.downloads".plinxLocalized)
        case .seerrDiscover:
            return .title("youtarr.explore.title".plinxLocalized)
        }
    }
}

struct PlinxTVShellHeader: View {
    let tabs: [KidsMainTabPicker.TabItem]
    let selectedTab: Binding<MainCoordinator.Tab>
    let selectedAction: KidsMainTabPicker.TabItem.Action?
    let leadingIdentity: PlinxTVShellLeadingIdentity
    let focusedTarget: FocusState<PlinxTVShellFocusTarget?>.Binding
    let onSelect: (MainCoordinator.Tab) -> Void
    let onAction: (KidsMainTabPicker.TabItem.Action) -> Void
    let onMoveDown: () -> Void
    var appearance: KidsMainTabPicker.SurfaceAppearance = .standard

    var body: some View {
        KidsMainTabPicker(
            tabs: tabs,
            selectedTab: selectedTab,
            selectedAction: selectedAction,
            focusedTarget: focusedTarget,
            onSelect: onSelect,
            onAction: onAction,
            onMoveDown: onMoveDown,
            placement: .header,
            surfaceAppearance: appearance
        )
        .overlay(alignment: .leading) {
            leadingIdentityView
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 4)
        .padding(.top, 1)
        .padding(.bottom, 4)
        .focusSection()
    }

    @ViewBuilder
    private var leadingIdentityView: some View {
        switch leadingIdentity {
        case .brand:
            PlinxHomeHeaderLogoView(
                accessibilityIdentifier: "tv.shell.logo",
                maxWidth: PlinxTVShellMetrics.logoMaxWidth,
                logoHeight: PlinxTVShellMetrics.logoHeight
            )
            .frame(maxWidth: 320, alignment: .leading)
            // The hero and rows intentionally reclaim half the tvOS leading
            // safe area. Pull the visible lockup onto that same content guide.
            .padding(.leading, PlinxTVShellMetrics.homeBrandLeadingInset)
            .accessibilityHidden(true)

        case let .title(title):
            Text(title)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(
                    appearance == .onBrightBrandSurface
                        ? PlinxBrand.shell
                        : Color.white.opacity(0.96)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .frame(width: 520, alignment: .leading)
                .padding(.leading, 28)
                .accessibilityIdentifier("tv.shell.context.title")
                .accessibilityValue(
                    appearance == .onBrightBrandSurface
                        ? "darkOnBrandGradient"
                        : "lightOnDarkShell"
                )
                .accessibilityAddTraits(.isHeader)
        }
    }
}
#endif

struct RootTabView: View {
    private struct QuickActionOption: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let role: ButtonRole?
        let action: () -> Void
    }

    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(ParentalAccessCoordinator.self) private var parentalAccessCoordinator
    @Environment(DownloadOwnershipStore.self) private var downloadOwnershipStore
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator
    @EnvironmentObject private var mainCoordinator: MainCoordinator
    @EnvironmentObject private var playbackLaunchCoordinator: PlaybackLaunchCoordinator
    @Environment(\.safetyPolicy) private var safetyPolicy

    @State private var showSettings = false
    @State private var youtarrExploreConfiguration: YoutarrConfiguration?
    @State private var isYoutarrConfigured = false
    @State private var selectedQuickActionMedia: MediaDisplayItem?
    @State private var quickActionErrorMessage: String?
    @State private var homeViewModel: SafeHomeViewModel?
    @State private var homeContentFocusRequest = 0
    @State private var libraryContentFocusRequest = 0
    @State private var searchContentFocusRequest = 0
    @State private var libraryDetailContentFocusRequest = 0
    @State private var detailContentFocusRequest = 0
    @State private var settingsContentFocusRequest = 0
    @State private var exploreContentFocusRequest = 0
    #if os(tvOS)
    @State private var mediaFocusModel = MediaFocusModel()
    @StateObject private var tvFocusCoordinator = PlinxTVFocusCoordinator()
    @State private var settingsNavigationCoordinator = PlinxSettingsNavigationCoordinator()
    @State private var settingsExitDestination: MainCoordinator.Tab?
    @State private var tvLibraryShellTitle: String?
    @FocusState private var focusedShellTarget: PlinxTVShellFocusTarget?
    @FocusState private var focusedQuickActionID: String?
    #endif
    /// Local overrides for watched status, keyed by media item id.
    /// Updated instantly on toggle; cleared when home data reloads.
    @State private var watchedOverrides: [String: Bool] = [:]
    @AppStorage(PlinxChromeButtonSizePreference.storageKey)
    private var chromeButtonSizeRaw = PlinxChromeButtonSizePreference.defaultValue.rawValue
    @AppStorage(PlinxNavigationPreference.showSearchInMainNavigationStorageKey)
    private var showSearchInMainNavigation = PlinxNavigationPreference.defaultShowSearchInMainNavigation
    @AppStorage(YoutarrExplorePreference.storageKey)
    private var isYoutarrExploreEnabled = YoutarrExplorePreference.defaultEnabled
    @AppStorage(YoutarrConfigurationStore.baseURLKey)
    private var youtarrStoredBaseURL = ""

    private var chromeButtonSize: PlinxChromeButtonSizePreference {
        PlinxChromeButtonSizePreference(rawValue: chromeButtonSizeRaw) ?? .medium
    }

    private var quickActionCornerRadius: CGFloat {
        #if os(tvOS)
        22
        #else
        14
        #endif
    }

    private var quickActionOptionMinHeight: CGFloat {
        #if os(tvOS)
        78
        #else
        52
        #endif
    }

    private var quickActionCancelMinHeight: CGFloat {
        #if os(tvOS)
        75
        #else
        50
        #endif
    }

    private var quickActionIconSize: CGFloat {
        #if os(tvOS)
        24
        #else
        16
        #endif
    }

    private var quickActionHorizontalPadding: CGFloat {
        #if os(tvOS)
        21
        #else
        14
        #endif
    }

    private var showsYoutarrExplore: Bool {
        if YoutarrLiveTestBootstrap.mainTabConfiguration() != nil {
            return true
        }
        return YoutarrExploreVisibility.shouldShow(
            isEnabled: isYoutarrExploreEnabled,
            isConfigured: isYoutarrConfigured
        )
    }

    private var launcher: PlaybackLauncher {
        PlaybackLauncher(
            context: plexApiContext,
            coordinator: mainCoordinator,
            safetyPolicy: safetyPolicy
        )
    }

    private var activeRootTab: MainCoordinator.Tab {
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

    private var hasDownloadActivity: Bool {
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
    private var visibleTabs: [KidsMainTabPicker.TabItem] {
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
    private var tabBinding: Binding<MainCoordinator.Tab> {
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

    private func quickActionSheet(for item: MediaDisplayItem) -> some View {
        let options = quickActionOptions(for: item)
        let optionIDs = options.map(\.id)
        return ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .accessibilityIdentifier("quickAction.backdrop")
                .onTapGesture {
                    selectedQuickActionMedia = nil
                }

            VStack(alignment: .leading, spacing: 12) {
                Text(item.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                ForEach(options) { option in
                    quickActionButton(option)
                }

                quickActionCancelButton
            }
            .padding(14)
            .liquidGlassBackground(style: PlinxTheme.Glass(cornerRadius: quickActionCornerRadius))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .accessibilityIdentifier("quickAction.sheet")
            #if os(tvOS)
            .focusSection()
            #endif
        }
        #if os(tvOS)
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                focusedQuickActionID = optionIDs.first ?? QuickActionFocusOrder.cancelID
            }
        }
        .onDisappear {
            focusedQuickActionID = nil
        }
        .onMoveCommand { direction in
            handleQuickActionMove(direction, optionIDs: optionIDs)
        }
        .onPlayPauseCommand {
            performFocusedQuickAction(options)
        }
        .onExitCommand {
            selectedQuickActionMedia = nil
        }
        #endif
    }

    private var quickActionCancelButton: some View {
        #if os(tvOS)
        let isFocused = focusedQuickActionID == QuickActionFocusOrder.cancelID
        #else
        let isFocused = false
        #endif

        return Button {
            selectedQuickActionMedia = nil
        } label: {
            Text(String(localized: "common.actions.cancel"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(maxWidth: .infinity, minHeight: quickActionCancelMinHeight)
                .background(
                    RoundedRectangle(cornerRadius: quickActionCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(isFocused ? 0.15 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: quickActionCornerRadius, style: .continuous)
                        .stroke(isFocused ? Color.accentColor.opacity(0.92) : .clear, lineWidth: isFocused ? 3 : 0)
                )
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .focused($focusedQuickActionID, equals: QuickActionFocusOrder.cancelID)
        #endif
        .accessibilityIdentifier("quickAction.cancel")
    }

    private func quickActionButton(_ option: QuickActionOption) -> some View {
        #if os(tvOS)
        let isFocused = focusedQuickActionID == option.id
        #else
        let isFocused = false
        #endif

        return Button(role: option.role) {
            performQuickAction(option.action)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.systemImage)
                    .font(.system(size: quickActionIconSize, weight: .semibold))
                Text(option.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, quickActionHorizontalPadding)
            .frame(maxWidth: .infinity, minHeight: quickActionOptionMinHeight)
            .background(
                RoundedRectangle(cornerRadius: quickActionCornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(isFocused ? 0.26 : 0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: quickActionCornerRadius, style: .continuous)
                    .stroke(Color.accentColor.opacity(isFocused ? 0.96 : 0.32), lineWidth: isFocused ? 3 : 1)
            )
        }
        .buttonStyle(PlinkButtonStyle())
        #if os(tvOS)
        .focused($focusedQuickActionID, equals: option.id)
        #endif
        .accessibilityIdentifier("quickAction.option.\(option.id)")
    }

    #if os(tvOS)
    private func handleQuickActionMove(_ direction: MoveCommandDirection, optionIDs: [String]) {
        let focusDirection: QuickActionFocusDirection
        switch direction {
        case .up:
            focusDirection = .up
        case .down:
            focusDirection = .down
        default:
            return
        }

        focusedQuickActionID = QuickActionFocusOrder.nextFocusedID(
            current: focusedQuickActionID,
            optionIDs: optionIDs,
            direction: focusDirection
        )
    }

    private func performFocusedQuickAction(_ options: [QuickActionOption]) {
        guard let focusedQuickActionID else { return }
        if focusedQuickActionID == QuickActionFocusOrder.cancelID {
            selectedQuickActionMedia = nil
            return
        }

        guard let option = options.first(where: { $0.id == focusedQuickActionID }) else { return }
        performQuickAction(option.action)
    }
    #endif

    private func performQuickAction(_ action: @escaping () -> Void) {
        selectedQuickActionMedia = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            action()
        }
    }

    @ViewBuilder
    private var mainTabView: some View {
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
    private var tabContainer: some View {
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
    private var tvOSShellHeader: some View {
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
    private var tvOSSettingsContent: some View {
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
    private func tabStack(for tab: MainCoordinator.Tab) -> some View {
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

    private func handleTabSelection(_ newValue: MainCoordinator.Tab) {
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

    private func handleBottomAction(_ action: KidsMainTabPicker.TabItem.Action) {
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

    private func closeSettings() {
        showSettings = false
    }

    private func normalizedRootTab(_ tab: MainCoordinator.Tab) -> MainCoordinator.Tab {
        if case .libraryDetail = tab { return .library }
        return tab
    }

    #if os(tvOS)
    private func contentRegion(for tab: MainCoordinator.Tab) -> PlinxTVContentRegion {
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

    private var visibleContentRegion: PlinxTVContentRegion {
        if activeRootTab == .library, !mainCoordinator.libraryPath.isEmpty {
            return .libraryDetail
        }
        return contentRegion(for: activeRootTab)
    }
    #endif

    private func requestHeaderFocus() {
        #if os(tvOS)
        let normalizedTab = normalizedRootTab(activeRootTab)
        let destination = HeaderFocusOrder.returnTarget(
            currentTab: normalizedTab,
            visibleTabs: visibleTabs
        ) ?? normalizedTab
        focusedShellTarget = .tab(destination)
        #endif
    }

    private func requestFirstContentFocus() {
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

    private var settingsHeaderRow: some View {
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

    private func scrollingHeaderContent(
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
    private func topTitleRow(
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

    private func refreshYoutarrConfigurationState() {
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

    @ViewBuilder
    private func destination(for route: MainCoordinator.Route) -> some View {
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
    private func tvDetailFocusRegion<Content: View>(_ content: Content) -> some View {
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

    private func makeHubDetailViewModel(hub: Hub) -> HubDetailViewModel {
        let viewModel = HubDetailViewModel(hub: hub, context: plexApiContext)
        let policy = safetyPolicy
        viewModel.itemFilter = {
            PlinxContentAuthorization.isAllowed($0, policy: policy)
        }
        return viewModel
    }

    private func handlePrimarySelection(_ displayItem: MediaDisplayItem) {
        switch displayItem {
        case let .playable(media):
            startPlayback(ratingKey: media.id, type: media.type)
        case let .collection(collection):
            mainCoordinator.showCollectionDetail(collection)
        case let .playlist(playlist):
            mainCoordinator.showPlaylistDetail(playlist)
        }
    }

    private func startPlayback(
        ratingKey: String,
        type: PlexItemType,
        shuffle: Bool = false,
        shouldResumeFromOffset: Bool = true
    ) {
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

    private func handlePlaybackResult(_ result: PlaybackLauncher.Result) {
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

    private func quickActionOptions(for item: MediaDisplayItem) -> [QuickActionOption] {
        switch item {
        case let .playable(media):
            var actions: [QuickActionOption] = [
                QuickActionOption(
                    id: "play",
                    title: String(localized: "common.actions.play"),
                    systemImage: "play.fill",
                    role: nil,
                    action: {
                        handlePrimarySelection(item)
                    }
                ),
                QuickActionOption(
                    id: "toggle-watched",
                    title: isWatched(media) ? "Mark as unwatched" : "Mark as watched",
                    systemImage: isWatched(media) ? "checkmark.circle.fill" : "checkmark.circle",
                    role: nil,
                    action: {
                        Task { await toggleWatched(media) }
                    }
                )
            ]

            #if !os(tvOS)
            switch QuickActionDownloadActionPolicy.action(for: media, downloadItems: downloadManager.items) {
            case .download:
                let downloadTitle: String
                switch media.type {
                case .show:
                    downloadTitle = "Download All Episodes"
                case .season:
                    downloadTitle = "Download Season"
                default:
                    downloadTitle = "Download Video"
                }

                actions.append(
                    QuickActionOption(
                        id: "download-\(media.id)",
                        title: downloadTitle,
                        systemImage: "arrow.down.circle",
                        role: nil,
                        action: {
                            guard PlinxContentAuthorization.isAllowed(media, policy: safetyPolicy) else {
                                quickActionErrorMessage = NSLocalizedString(
                                    "downloads.blockedByContentControls",
                                    tableName: "Plinx",
                                    comment: ""
                                )
                                return
                            }
                            Task {
                                guard let ownerIdentity = sessionManager.plinxDownloadOwnerIdentity else {
                                    quickActionErrorMessage = NSLocalizedString(
                                        "downloads.ownerUnavailable",
                                        tableName: "Plinx",
                                        comment: ""
                                    )
                                    return
                                }
                                let newDownloadIDs: [String]
                                switch media.type {
                                case .show:
                                    newDownloadIDs = await downloadManager.enqueueShow(
                                        ratingKey: media.id,
                                        context: plexApiContext
                                    )
                                case .season:
                                    newDownloadIDs = await downloadManager.enqueueSeason(
                                        ratingKey: media.id,
                                        context: plexApiContext
                                    )
                                default:
                                    newDownloadIDs = await downloadManager.enqueueItem(
                                        ratingKey: media.id,
                                        context: plexApiContext
                                    )
                                }
                                downloadOwnershipStore.claim(
                                    downloadIDs: newDownloadIDs,
                                    as: ownerIdentity
                                )
                            }
                        }
                    )
                )
            case .goToDownloads:
                actions.append(
                    QuickActionOption(
                        id: "go-downloads-\(media.id)",
                        title: "Go to downloads",
                        systemImage: "arrow.down.circle.fill",
                        role: nil,
                        action: {
                            mainCoordinator.resetToRoot(for: .more)
                            mainCoordinator.tab = .more
                        }
                    )
                )
            }
            #endif

            actions.append(
                QuickActionOption(
                    id: "go-details",
                    title: "Go to details",
                    systemImage: "info.circle",
                    role: nil,
                    action: {
                        mainCoordinator.showMediaDetail(media)
                    }
                )
            )

            return actions

        case let .collection(collection):
            return [
                QuickActionOption(
                    id: "collection-details-\(collection.id)",
                    title: "Go to details",
                    systemImage: "info.circle",
                    role: nil,
                    action: {
                        mainCoordinator.showCollectionDetail(collection)
                    }
                )
            ]

        case let .playlist(playlist):
            return [
                QuickActionOption(
                    id: "playlist-play-\(playlist.id)",
                    title: String(localized: "common.actions.play"),
                    systemImage: "play.fill",
                    role: nil,
                    action: {
                        handlePrimarySelection(item)
                    }
                ),
                QuickActionOption(
                    id: "playlist-details-\(playlist.id)",
                    title: "Go to details",
                    systemImage: "info.circle",
                    role: nil,
                    action: {
                        mainCoordinator.showPlaylistDetail(playlist)
                    }
                )
            ]
        }
    }

    private func toggleWatched(_ item: MediaItem) async {
        let wasWatched = isWatched(item)
        
        // Optimistic local update — instant UI feedback
        watchedOverrides[item.id] = !wasWatched
        selectedQuickActionMedia = nil
        
        do {
            let scrobbleRepository = try ScrobbleRepository(context: plexApiContext)
            if wasWatched {
                try await scrobbleRepository.markUnwatched(key: item.id)
            } else {
                try await scrobbleRepository.markWatched(key: item.id)
            }
            // Reload from server to refresh home data. Keep the successful
            // local override in place so independently owned library view
            // models cannot briefly revert to stale watch state.
            await homeViewModel?.reload()
        } catch {
            // Revert optimistic update on failure
            watchedOverrides.removeValue(forKey: item.id)
            quickActionErrorMessage = error.localizedDescription
        }
    }

    private func isWatched(_ item: MediaItem) -> Bool {
        // Check local override first (instant feedback)
        if let override = watchedOverrides[item.id] {
            return override
        }
        guard let playableType = PlayableItemType(plexType: item.type) else { return false }

        switch playableType {
        case .movie, .episode, .clip:
            return (item.viewCount ?? 0) > 0
        case .show, .season:
            guard let leafCount = item.leafCount, let viewedLeafCount = item.viewedLeafCount else {
                return false
            }
            guard leafCount > 0 else { return false }
            return leafCount == viewedLeafCount
        }
    }

    private func isWatchedDisplay(_ item: MediaDisplayItem) -> Bool {
        guard let media = item.playableItem else { return false }
        return isWatched(media)
    }

}

#if !os(tvOS)
struct PlinxScrollingHeaderRow: View {
    let title: String
    let showsSettingsButton: Bool
    let showsSearchButton: Bool
    let showsLogo: Bool
    let chromeButtonSize: PlinxChromeButtonSizePreference
    let onSearch: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            leadingContent
            Spacer()

            if showsSearchButton {
                PlinxChromeButton(systemImage: "magnifyingglass", action: onSearch)
                    .accessibilityIdentifier("home.header.search")
            }

            if showsSettingsButton {
                PlinxChromeButton(systemImage: "gearshape.fill", action: onSettings)
                    .accessibilityIdentifier("home.header.settings")
            } else if !showsSearchButton {
                Color.clear
                    .frame(width: chromeButtonSize.sideLength, height: chromeButtonSize.sideLength)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var leadingContent: some View {
        if showsLogo {
            let logoHeight = PlinxBrandLayoutMetrics.homeHeaderLogoHeight(
                chromeButtonSideLength: chromeButtonSize.sideLength
            )
            PlinxHomeHeaderLogoView(
                accessibilityIdentifier: "home.header.logo",
                maxWidth: PlinxBrandLayoutMetrics.homeHeaderLogoWidth(
                    chromeButtonSideLength: chromeButtonSize.sideLength
                ),
                logoHeight: logoHeight
            )
        } else {
            Text(title.plinxLocalized)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
        }
    }
}
#endif

extension String {
    var plinxLocalized: String {
        NSLocalizedString(self, tableName: "Plinx", bundle: .main, comment: "")
    }
}
