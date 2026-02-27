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
        case .library, .libraryDetail:
            return .library
        case .downloads:
            return .downloads
        case .home, .more, .seerrDiscover:
            return .home
        }
    }

    /// Tabs shown in the picker — downloads tab auto-hides when empty.
    private var visibleTabs: [KidsMainTabPicker.TabItem] {
        var tabs = KidsMainTabPicker.TabItem.mainTabs()
        if !downloadManager.sortedItems.isEmpty {
            tabs.append(KidsMainTabPicker.TabItem(
                id: "downloads",
                tab: .downloads,
                iconName: "arrow.down.circle.fill",
                title: LocalizedStringResource("tabs.downloads", table: "Plinx")
            ))
        }
        return tabs
    }

    /// Maps coordinator tab to tab-bar selection.
    private var tabBinding: Binding<MainCoordinator.Tab> {
        Binding(
            get: { activeRootTab },
            set: { newValue in
                if newValue == activeRootTab {
                    mainCoordinator.popToRoot(for: newValue)
                }
                mainCoordinator.tab = newValue
            }
        )
    }

    var body: some View {
        mainTabView
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

        // Keep root tab chrome fully custom (KidsMainTabPicker only).
        base
    }

    private var tabContainer: some View {
        ZStack {
            tabStack(for: .home)
            tabStack(for: .search)
            tabStack(for: .library)
            tabStack(for: .downloads)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                PlinxSettingsView()
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showSettings = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.title3)
                            }
                        }
                    }
            }
            .presentationDetents([.large])
        }
    }

    @ViewBuilder
    private func tabStack(for tab: MainCoordinator.Tab) -> some View {
        switch tab {
        case .home:
            NavigationStack(path: mainCoordinator.pathBinding(for: .home)) {
                PlinxHomeView(
                    viewModel: SafeHomeViewModel(
                        inner: HomeViewModel(
                            context: plexApiContext,
                            settingsManager: settingsManager,
                            libraryStore: libraryStore
                        ),
                        policy: safetyPolicy
                    ),
                    topContent: AnyView(topTitleRow(title: "tabs.home", showsSettingsButton: true, showsLogo: true)),
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
            .opacity(activeRootTab == .home ? 1 : 0)
            .allowsHitTesting(activeRootTab == .home)
            .accessibilityHidden(activeRootTab != .home)

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
                    LibraryDetailView(
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

        case .more, .seerrDiscover, .libraryDetail:
            EmptyView()

        case .downloads:
            NavigationStack(path: mainCoordinator.pathBinding(for: .downloads)) {
                DownloadsView()
                    .safeAreaInset(edge: .top, spacing: 0) {
                        topTitleRow(title: "tabs.downloads", showsSettingsButton: false)
                    }
                    .toolbar(.hidden, for: .navigationBar)
            }
            .opacity(activeRootTab == .downloads ? 1 : 0)
            .allowsHitTesting(activeRootTab == .downloads)
            .accessibilityHidden(activeRootTab != .downloads)
        }
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
                    .frame(height: 28)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white.opacity(0.95))
            Spacer()
            if showsSettingsButton {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 52, height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                        )
                }
            } else {
                Color.clear
                    .frame(width: 52, height: 52)
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

            if let seriesKey = seriesRatingKey(for: media) {
                actions.append(
                    QuickActionOption(
                        id: "go-series-\(seriesKey)",
                        title: "Go to series",
                        systemImage: "tv",
                        role: nil,
                        action: {
                            Task { await showDetail(for: seriesKey) }
                        }
                    )
                )
            }

            if let seasonKey = seasonRatingKey(for: media) {
                actions.append(
                    QuickActionOption(
                        id: "go-season-\(seasonKey)",
                        title: "Go to season",
                        systemImage: "rectangle.stack",
                        role: nil,
                        action: {
                            Task { await showDetail(for: seasonKey) }
                        }
                    )
                )
            }

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
        do {
            let scrobbleRepository = try ScrobbleRepository(context: plexApiContext)
            if isWatched(item) {
                try await scrobbleRepository.markUnwatched(key: item.id)
            } else {
                try await scrobbleRepository.markWatched(key: item.id)
            }
        } catch {
            quickActionErrorMessage = error.localizedDescription
        }
    }

    private func showDetail(for ratingKey: String) async {
        do {
            let metadataRepository = try MetadataRepository(context: plexApiContext)
            let response = try await metadataRepository.getMetadata(ratingKey: ratingKey)
            guard
                let plexItem = response.mediaContainer.metadata?.first,
                let playable = PlayableMediaItem(plexItem: plexItem)
            else {
                return
            }
            mainCoordinator.showMediaDetail(playable)
        } catch {
            quickActionErrorMessage = error.localizedDescription
        }
    }

    private func isWatched(_ item: MediaItem) -> Bool {
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

    private func seasonRatingKey(for item: MediaItem) -> String? {
        guard item.type == .episode else { return nil }
        return item.parentRatingKey
    }

    private func seriesRatingKey(for item: MediaItem) -> String? {
        switch item.type {
        case .episode:
            return item.grandparentRatingKey ?? item.parentRatingKey
        case .season:
            return item.parentRatingKey
        default:
            return nil
        }
    }
}
