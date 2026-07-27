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
    static func nextPreferredTab(
        current: MainCoordinator.Tab,
        visibleTabs: [KidsMainTabPicker.TabItem]
    ) -> MainCoordinator.Tab? {
        visibleTabs
            .compactMap(\.tab)
            .first(where: { $0 != current })
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
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator
    @EnvironmentObject private var mainCoordinator: MainCoordinator
    @Environment(\.safetyPolicy) private var safetyPolicy

    @State private var showSettings = false
    @State private var selectedQuickActionMedia: MediaDisplayItem?
    @State private var quickActionErrorMessage: String?
    @State private var homeViewModel: SafeHomeViewModel?
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
        case .home, .seerrDiscover:
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
            .overlay(alignment: .bottom) {
                if let item = selectedQuickActionMedia {
                    quickActionSheet(for: item)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.86), value: selectedQuickActionMedia != nil)
            .alert("Action Failed", isPresented: Binding(
                get: { quickActionErrorMessage != nil },
                set: { if !$0 { quickActionErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                PlinxSettingsView()
                    .toolbar(.hidden, for: .navigationBar)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        settingsHeaderRow
                    }
            }
            #if !os(tvOS)
            .presentationDetents([.large])
            #endif
        }
    }

    @ViewBuilder
    private func tabStack(for tab: MainCoordinator.Tab) -> some View {
        switch tab {
        case .home:
            let viewModel = homeViewModel ?? SafeHomeViewModel(
                inner: HomeViewModel(
                    context: plexApiContext,
                    settingsManager: settingsManager,
                    libraryStore: libraryStore
                ),
                policy: safetyPolicy,
                libraryStore: libraryStore
            )
            
            NavigationStack(path: mainCoordinator.pathBinding(for: .home)) {
                PlinxHomeView(
                    viewModel: viewModel,
                    topContent: scrollingHeaderContent(
                        title: "tabs.home",
                        showsSettingsButton: false,
                        showsSearchButton: false,
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
                        context: plexApiContext
                    ),
                    topContent: scrollingHeaderContent(title: "tabs.library".plinxLocalized, showsSettingsButton: false),
                    onSelectLibrary: { library in
                        mainCoordinator.libraryPath.append(library)
                    },
                    onRequestHomeNavigationFocus: {
                        requestHeaderFocus(from: .library)
                    }
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

        case .seerrDiscover, .libraryDetail(_):
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
            showSettings = true
        }
    }

    private func requestHeaderFocus(from currentTab: MainCoordinator.Tab) {
        #if os(tvOS)
        focusedHeaderTab = HeaderFocusOrder.nextPreferredTab(
            current: currentTab,
            visibleTabs: visibleTabs
        ) ?? currentTab
        #endif
    }

    private var settingsHeaderRow: some View {
        HStack(spacing: 12) {
            Text("tabs.settings".plinxLocalized)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white.opacity(0.95))
            Spacer()
            PlinxChromeButton(systemImage: "xmark") {
                showSettings = false
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
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
        HStack(spacing: 12) {
            headerLeadingContent(title: title, showsLogo: showsLogo)
            Spacer()
            if showsSearchButton {
                PlinxChromeButton(systemImage: "magnifyingglass") {
                    handleTabSelection(.search)
                }
                .accessibilityIdentifier("home.header.search")
            }
            if showsSettingsButton {
                PlinxChromeButton(systemImage: "gearshape.fill") {
                    showSettings = true
                }
                .accessibilityIdentifier("home.header.settings")
            } else if !showsSearchButton {
                Color.clear
                    .frame(width: chromeButtonSize.sideLength, height: chromeButtonSize.sideLength)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        #endif
    }

    @ViewBuilder
    private func headerLeadingContent(title: String, showsLogo: Bool) -> some View {
        if showsLogo {
            HStack(spacing: 10) {
                Image("LogoColor")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 35)
                    .accessibilityHidden(true)

                Text(title.plinxLocalized)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
            }
        } else {
            Text(title.plinxLocalized)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
        }
    }

    private var tvOSHeaderOverlayWidth: CGFloat {
        280
    }

    private var tvOSHeaderOverlayLeadingPadding: CGFloat {
        14
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
                    Task { await launcher.play(ratingKey: ratingKey, type: type) }
                },
                onShuffle: { ratingKey, type in
                    Task { await launcher.play(ratingKey: ratingKey, type: type, shuffle: true) }
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
            #if os(tvOS)
            PlaylistDetailTVView(
                viewModel: makePlaylistDetailViewModel(playlist: playlist),
                onSelectMedia: { displayItem in
                    mainCoordinator.showMediaDetail(displayItem)
                },
                onPlay: { ratingKey in
                    Task { await launcher.play(ratingKey: ratingKey, type: playlist.type) }
                },
                onShuffle: { ratingKey in
                    Task { await launcher.play(ratingKey: ratingKey, type: playlist.type, shuffle: true) }
                }
            )
            #else
            PlaylistDetailView(
                viewModel: makePlaylistDetailViewModel(playlist: playlist),
                onSelectMedia: { displayItem in
                    mainCoordinator.showMediaDetail(displayItem)
                },
                onPlay: { ratingKey in
                    Task { await launcher.play(ratingKey: ratingKey, type: playlist.type) }
                },
                onShuffle: { ratingKey in
                    Task { await launcher.play(ratingKey: ratingKey, type: playlist.type, shuffle: true) }
                }
            )
            #endif
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
            StrimrAdapter.isAllowed($0, policy: policy)
        }
        return viewModel
    }

    private func makePlaylistDetailViewModel(
        playlist: PlaylistMediaItem
    ) -> PlaylistDetailViewModel {
        let viewModel = PlaylistDetailViewModel(
            playlist: playlist,
            context: plexApiContext
        )
        let policy = safetyPolicy
        viewModel.itemFilter = {
            StrimrAdapter.isAllowed($0, policy: policy)
        }
        return viewModel
    }

    private func handlePrimarySelection(_ displayItem: MediaDisplayItem) {
        switch displayItem {
        case let .playable(media):
            Task { await launcher.play(ratingKey: media.id, type: media.type) }
        case let .collection(collection):
            mainCoordinator.showCollectionDetail(collection)
        case let .playlist(playlist):
            Task { await launcher.play(ratingKey: playlist.id, type: playlist.type) }
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
                            Task {
                                switch media.type {
                                case .show:
                                    await downloadManager.enqueueShow(ratingKey: media.id, context: plexApiContext)
                                case .season:
                                    await downloadManager.enqueueSeason(ratingKey: media.id, context: plexApiContext)
                                default:
                                    await downloadManager.enqueueItem(ratingKey: media.id, context: plexApiContext)
                                }
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

extension String {
    var plinxLocalized: String {
        NSLocalizedString(self, tableName: "Plinx", bundle: .main, comment: "")
    }
}
