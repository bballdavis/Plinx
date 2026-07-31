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
        visibleTabs: [KidsMainTabPicker.TabItem]
    ) -> MainCoordinator.Tab? {
        visibleTabs
            .compactMap(\.tab)
            .first(where: { $0 == .home })
            ?? visibleTabs.compactMap(\.tab).first
    }
}

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
    @Environment(\.safetyPolicy) private var safetyPolicy

    @State private var showSettings = false
    @State private var youtarrExploreConfiguration: YoutarrConfiguration?
    @State private var isYoutarrConfigured = false
    @State private var selectedQuickActionMedia: MediaDisplayItem?
    @State private var quickActionErrorMessage: String?
    @State private var homeViewModel: SafeHomeViewModel?
    @State private var homeContentFocusRequest = 0
    @State private var libraryContentFocusRequest = 0
    #if os(tvOS)
    @State private var mediaFocusModel = MediaFocusModel()
    @FocusState private var focusedHeaderTab: MainCoordinator.Tab?
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
        YoutarrExploreVisibility.shouldShow(
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
            #if os(tvOS)
            .allowsHitTesting(selectedQuickActionMedia == nil)
            #endif
            #if os(tvOS)
            .onAppear {
                focusedHeaderTab = activeRootTab
            }
            .onChange(of: activeRootTab) { _, newTab in
                focusedHeaderTab = newTab
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
            .overlay(alignment: .bottom) {
                if let item = selectedQuickActionMedia {
                    quickActionSheet(for: item)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.86), value: selectedQuickActionMedia != nil)
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
        let base = tabContainer
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .tabBar)
            .environment(\.watchedOverrides, watchedOverrides)
            #if os(tvOS)
            .environment(mediaFocusModel)
            #endif

        #if os(tvOS)
        base
        #else
        base
            .safeAreaInset(edge: .bottom, spacing: 0) {
                KidsMainTabPicker(
                    tabs: visibleTabs,
                    selectedTab: tabBinding,
                    onAction: handleBottomAction
                )
            }
        #endif
    }

    private var tabContainer: some View {
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
            #if !os(tvOS)
            .presentationDetents([.large])
            #else
            .frame(width: 1_440, height: 900)
            .background(Color.appBackground)
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            #endif
        }
        .onChange(of: showSettings) { _, isPresented in
            if !isPresented {
                parentalAccessCoordinator.lock()
                refreshYoutarrConfigurationState()
            }
        }
    }

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
                        requestHeaderFocus(from: .home)
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
                        mainCoordinator.libraryPath.append(library)
                    },
                    onRequestHomeNavigationFocus: {
                        requestHeaderFocus(from: .library)
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
                        }
                    )
                }
                .navigationDestination(for: MainCoordinator.Route.self) { route in
                    destination(for: route)
                }
            }
            .opacity(activeRootTab == .library ? 1 : 0)
            .allowsHitTesting(activeRootTab == .library)
            .accessibilityHidden(activeRootTab != .library)

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
                        isActive: activeRootTab == .seerrDiscover
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
        mainCoordinator.resetToRoot(for: newValue)
        mainCoordinator.tab = newValue
    }

    private func handleBottomAction(_ action: KidsMainTabPicker.TabItem.Action) {
        switch action {
        case .settings:
            parentalAccessCoordinator.lock()
            showSettings = true
        }
    }

    private func requestHeaderFocus(from currentTab: MainCoordinator.Tab) {
        #if os(tvOS)
        focusedHeaderTab = HeaderFocusOrder.returnTarget(visibleTabs: visibleTabs) ?? currentTab
        #endif
    }

    private func requestFirstContentFocus() {
        #if os(tvOS)
        switch activeRootTab {
        case .home:
            homeContentFocusRequest &+= 1
        case .library:
            libraryContentFocusRequest &+= 1
        default:
            break
        }
        #endif
    }

    private var settingsHeaderRow: some View {
        HStack(spacing: 12) {
            Text("tabs.settings".plinxLocalized)
                #if os(tvOS)
                .font(.system(size: 46, weight: .bold, design: .rounded))
                #else
                .font(.title3.weight(.bold))
                #endif
                .foregroundStyle(.white.opacity(0.95))
            Spacer()
            PlinxChromeButton(systemImage: "xmark") {
                showSettings = false
            }
        }
        #if os(tvOS)
        .padding(.horizontal, 42)
        .padding(.top, 26)
        .padding(.bottom, 20)
        #else
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
        AnyView(
            topTitleRow(
                title: title,
                showsSettingsButton: showsSettingsButton,
                showsSearchButton: showsSearchButton,
                showsLogo: showsLogo
            )
        )
    }

    private func topTitleRow(
        title: String,
        showsSettingsButton: Bool,
        showsSearchButton: Bool = false,
        showsLogo: Bool = false
    ) -> some View {
        #if os(tvOS)
        KidsMainTabPicker(
            tabs: visibleTabs,
            selectedTab: tabBinding,
            focusedTab: $focusedHeaderTab,
            onAction: handleBottomAction,
            onMoveDown: requestFirstContentFocus,
            placement: .header
        )
        .overlay(alignment: .leading) {
            headerLeadingContent(title: title, showsLogo: showsLogo)
                .frame(maxWidth: tvOSHeaderOverlayWidth, alignment: .leading)
                .padding(.leading, tvOSHeaderOverlayLeadingPadding)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 4)
        .padding(.top, 1)
        .padding(.bottom, 4)
        #else
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
        #endif
    }

    @ViewBuilder
    private func headerLeadingContent(title: String, showsLogo: Bool) -> some View {
        if showsLogo {
            PlinxHomeHeaderLogoView(
                accessibilityIdentifier: "home.header.logo",
                maxWidth: 220,
                logoHeight: 52
            )
        } else {
            Text(title.plinxLocalized)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
        }
    }

    private var tvOSHeaderOverlayWidth: CGFloat {
        320
    }

    private var tvOSHeaderOverlayLeadingPadding: CGFloat {
        14
    }

    private func refreshYoutarrConfigurationState() {
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
            PlinxMediaDetailView(
                viewModel: SafeMediaDetailViewModel(
                    inner: MediaDetailViewModel(
                        media: media,
                        context: plexApiContext
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
                }
            )
        case let .collectionDetail(collection):
            PlinxCollectionDetailView(
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
                }
            )
        case let .playlistDetail(playlist):
            PlinxPlaylistDetailView(
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
                }
            )
        case let .hubDetail(hub):
            HubDetailView(
                viewModel: makeHubDetailViewModel(hub: hub),
                onSelectMedia: { displayItem in
                    mainCoordinator.showMediaDetail(displayItem)
                }
            )
        }
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
        Task { @MainActor in
            let result = await launcher.play(
                ratingKey: ratingKey,
                type: type,
                shuffle: shuffle,
                shouldResumeFromOffset: shouldResumeFromOffset
            )
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
