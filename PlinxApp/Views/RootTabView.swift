import SwiftUI
import PlinxCore
import PlinxUI

struct RootTabView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @EnvironmentObject private var mainCoordinator: MainCoordinator
    @Environment(\.safetyPolicy) private var safetyPolicy
    @Environment(\.openURL) private var openURL

    @State private var showSettings = false

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
        case .home, .more, .seerrDiscover:
            return .home
        }
    }

    /// Maps coordinator tab to tab-bar selection.
    private var tabBinding: Binding<MainCoordinator.Tab> {
        Binding(
            get: { activeRootTab },
            set: { mainCoordinator.tab = $0 }
        )
    }

    var body: some View {
        mainTabView
    }

    @ViewBuilder
    private var mainTabView: some View {
        // Build the base view: native tab bar hidden, with custom bottom bar.
        let base = tabContainer
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                KidsMainTabPicker(
                    tabs: KidsMainTabPicker.TabItem.mainTabs(),
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                PlinxSettingsView()
                    .navigationTitle(Text("tabs.settings", tableName: "Plinx"))
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
                    topContent: AnyView(topTitleRow(title: "tabs.home")),
                    onSelectMedia: { displayItem in
                        switch displayItem {
                        case let .playable(media):
                            Task { await launcher.play(ratingKey: media.id, type: media.type) }
                        case let .collection(collection):
                            mainCoordinator.showCollectionDetail(collection)
                        case let .playlist(playlist):
                            Task { await launcher.play(ratingKey: playlist.id, type: playlist.type) }
                        }
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
                    topContent: AnyView(topTitleRow(title: "tabs.search")),
                    onSelectMedia: { displayItem in
                        switch displayItem {
                        case let .playable(media):
                            Task { await launcher.play(ratingKey: media.id, type: media.type) }
                        case let .collection(collection):
                            mainCoordinator.showCollectionDetail(collection)
                        case let .playlist(playlist):
                            Task { await launcher.play(ratingKey: playlist.id, type: playlist.type) }
                        }
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
                    topContent: AnyView(topTitleRow(title: "tabs.libraries")),
                    onSelectLibrary: { library in
                        mainCoordinator.libraryPath.append(library)
                    }
                )
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Library.self) { library in
                    LibraryDetailView(
                        library: library,
                        onSelectMedia: { displayItem in
                            switch displayItem {
                            case let .playable(media):
                                Task { await launcher.play(ratingKey: media.id, type: media.type) }
                            case let .collection(collection):
                                mainCoordinator.showCollectionDetail(collection)
                            case let .playlist(playlist):
                                Task { await launcher.play(ratingKey: playlist.id, type: playlist.type) }
                            }
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
        }
    }

    private func topTitleRow(title: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white.opacity(0.95))
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
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
}
