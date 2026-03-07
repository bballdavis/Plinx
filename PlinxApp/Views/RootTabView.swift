import SwiftUI
import PlinxCore
import PlinxUI

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
    @EnvironmentObject private var mainCoordinator: MainCoordinator
    @Environment(\.safetyPolicy) private var safetyPolicy
    @Environment(\.openURL) private var openURL

    @State private var showSettings = false
    @State private var selectedQuickActionMedia: MediaDisplayItem?
    @State private var quickActionErrorMessage: String?
    @State private var homeViewModel: SafeHomeViewModel?
    /// Local overrides for watched status, keyed by media item id.
    /// Updated instantly on toggle; cleared when home data reloads.
    @State private var watchedOverrides: [String: Bool] = [:]
    @AppStorage(PlinxChromeButtonSizePreference.storageKey)
    private var chromeButtonSizeRaw = PlinxChromeButtonSizePreference.defaultValue.rawValue

    private var chromeButtonSize: PlinxChromeButtonSizePreference {
        PlinxChromeButtonSizePreference(rawValue: chromeButtonSizeRaw) ?? .medium
    }

    private var launcher: PlaybackLauncher {
        PlaybackLauncher(
            context: plexApiContext,
            coordinator: mainCoordinator,
            settingsManager: settingsManager,
            openURL: { url in openURL(url) }
        )
    }

    private var activeRootTab: MainCoordinator.Tab {
        switch mainCoordinator.tab {
        case .search:
            return .search
        case .library, .libraryDetail(_):
            return .library
        case .downloads, .more:
            return .more
        case .home, .seerrDiscover:
            return .home
        }
    }

    private var hasDownloadActivity: Bool {
        !downloadManager.items.isEmpty
    }

    /// Tabs shown in the picker.
    private var visibleTabs: [KidsMainTabPicker.TabItem] {
        KidsMainTabPicker.TabItem.mainTabs(includeDownloads: hasDownloadActivity)
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
            .onChange(of: hasDownloadActivity) { _, hasDownloads in
                guard !hasDownloads, activeRootTab == .more else { return }
                mainCoordinator.resetToRoot(for: .more)
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
        ZStack(alignment: .bottom) {
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

                ForEach(quickActionOptions(for: item)) { option in
                    quickActionButton(option)
                }

                Button {
                    selectedQuickActionMedia = nil
                } label: {
                    Text(String(localized: "common.actions.cancel"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quickAction.cancel")
            }
            .padding(14)
            .liquidGlassBackground()
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .accessibilityIdentifier("quickAction.sheet")
        }
    }

    private func quickActionButton(_ option: QuickActionOption) -> some View {
        Button(role: option.role) {
            performQuickAction(option.action)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(option.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.32), lineWidth: 1)
            )
        }
        .buttonStyle(PlinkButtonStyle())
        .accessibilityIdentifier("quickAction.option.\(option.id)")
    }

    private func performQuickAction(_ action: @escaping () -> Void) {
        selectedQuickActionMedia = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            action()
        }
    }

    @ViewBuilder
    private var mainTabView: some View {
        // Build the base view: native tab bar hidden, with custom bottom bar.
        let base = tabContainer
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                KidsMainTabPicker(
                    tabs: visibleTabs,
                    selectedTab: tabBinding
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.watchedOverrides, watchedOverrides)

        // Keep root tab chrome fully custom (KidsMainTabPicker only).
        base
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
            .presentationDetents([.large])
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
                    topContent: AnyView(topTitleRow(title: "tabs.home", showsSettingsButton: true, showsLogo: true)),
                    onSelectMedia: { displayItem in
                        handlePrimarySelection(displayItem)
                    },
                    onLongPressMedia: { displayItem in
                        selectedQuickActionMedia = displayItem
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
                        inner: SearchViewModel(context: plexApiContext),
                        policy: safetyPolicy
                    ),
                    topContent: AnyView(topTitleRow(title: "tabs.search", showsSettingsButton: false)),
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
                    topContent: AnyView(topTitleRow(title: "tabs.libraries", showsSettingsButton: false)),
                    onSelectLibrary: { library in
                        mainCoordinator.libraryPath.append(library)
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

        case .downloads, .more:
            NavigationStack(path: mainCoordinator.pathBinding(for: .more)) {
                PlinxDownloadsGridView()
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: MainCoordinator.Route.self) { route in
                        destination(for: route)
                    }
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

    private var settingsHeaderRow: some View {
        HStack(spacing: 12) {
            Text("tabs.settings", tableName: "Plinx")
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

    private func topTitleRow(
        title: LocalizedStringKey,
        showsSettingsButton: Bool,
        showsLogo: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            if showsLogo {
                Image("LogoColor")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 35)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white.opacity(0.95))
            } else {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            Spacer()
            if showsSettingsButton {
                PlinxChromeButton(systemImage: "gearshape.fill") {
                    showSettings = true
                }
            } else {
                Color.clear
                    .frame(width: chromeButtonSize.sideLength, height: chromeButtonSize.sideLength)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
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
                onSelectRelated: { displayItem in
                    mainCoordinator.showMediaDetail(displayItem)
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
            // Playlists are a new feature; show placeholder for now
            AnyView(
                VStack(spacing: 16) {
                    Text(playlist.title)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Playlist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
            )
        }
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

            // Download option — handles show/season/episode/movie/clip
            let downloadTitle: String
            let downloadIcon = "arrow.down.circle"
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
                    systemImage: downloadIcon,
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
