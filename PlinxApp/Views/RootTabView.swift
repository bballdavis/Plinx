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

    /// Maps coordinator tab to tab-bar selection, collapsing `.more` → `.home`
    private var tabBinding: Binding<MainCoordinator.Tab> {
        Binding(
            get: {
                let t = mainCoordinator.tab
                return (t == .more) ? .home : t
            },
            set: { mainCoordinator.tab = $0 }
        )
    }

    var body: some View {
        mainTabView
    }

    @ViewBuilder
    private var mainTabView: some View {
        // Build the base view: native tab bar hidden, our liquid glass picker
        // floated as a safe-area inset so it sits above the home indicator.
        // Settings gear is a floating overlay so we can fully hide the nav bar
        // on root tabs (no chrome, no title bar at all).
        let base = tabContainer
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                KidsMainTabPicker(
                    tabs: KidsMainTabPicker.TabItem.mainTabs(),
                    selectedTab: tabBinding
                )
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.top, 12)
                .padding(.trailing, 20)
            }

        if #available(iOS 18.0, *) {
            // Suppress the iOS 18 adaptive sidebar / top navigation on iPad.
            base.tabViewStyle(.tabBarOnly)
        } else {
            base
        }
    }

    private var tabContainer: some View {
        TabView(selection: tabBinding) {
            // MARK: Home
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
                .navigationTitle(Text("tabs.home", tableName: "Plinx"))
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: MainCoordinator.Route.self) { route in
                    destination(for: route)
                }
            }
            .tag(MainCoordinator.Tab.home)

            // MARK: Search
            NavigationStack(path: mainCoordinator.pathBinding(for: .search)) {
                PlinxSearchView(
                    viewModel: SafeSearchViewModel(
                        inner: SearchViewModel(context: plexApiContext),
                        policy: safetyPolicy
                    ),
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
                .navigationTitle(Text("tabs.search", tableName: "Plinx"))
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: MainCoordinator.Route.self) { route in
                    destination(for: route)
                }
            }
            .tag(MainCoordinator.Tab.search)

            // MARK: Library
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
                    onSelectLibrary: { library in
                        mainCoordinator.libraryPath.append(library)
                    }
                )
                .navigationTitle(Text("tabs.library", tableName: "Plinx"))
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
            .tag(MainCoordinator.Tab.library)
        }
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
