import SwiftUI
import PlinxCore
import PlinxUI

struct RootTabView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(MainCoordinator.self) private var mainCoordinator
    @Environment(\.openURL) private var openURL

    private var launcher: PlaybackLauncher {
        PlaybackLauncher(
            context: plexApiContext,
            coordinator: mainCoordinator,
            settingsManager: settingsManager,
            openURL: { url in openURL(url) }
        )
    }

    var body: some View {
        @Bindable var coordinator = mainCoordinator
        
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            Group {
                switch mainCoordinator.tab {
                case .home:
                    NavigationStack(path: $coordinator.homePath) {
                        HomeView(
                            viewModel: HomeViewModel(
                                context: plexApiContext,
                                settingsManager: settingsManager,
                                libraryStore: libraryStore
                            ),
                            onSelectMedia: { displayItem in
                                switch displayItem {
                                case let .playable(media):
                                    Task {
                                        await launcher.play(ratingKey: media.id, type: media.type)
                                    }
                                case .collection:
                                    // Collections handle their own navigation or selection
                                    break
                                }
                            }
                        )
                        .navigationTitle("Home")
                        .navigationDestination(for: MainCoordinator.Route.self) { route in
                            destination(for: route)
                        }
                    }
                case .library:
                    NavigationStack(path: $coordinator.libraryPath) {
                        LibraryView(
                            viewModel: LibraryViewModel(
                                context: plexApiContext,
                                libraryStore: libraryStore
                            ),
                            onSelectMedia: { displayItem in
                                switch displayItem {
                                case let .playable(media):
                                    Task {
                                        await launcher.play(ratingKey: media.id, type: media.type)
                                    }
                                case .collection:
                                    break
                                }
                            }
                        )
                        .navigationTitle("Library")
                        .navigationDestination(for: MainCoordinator.Route.self) { route in
                            destination(for: route)
                        }
                    }
                case .search:
                    NavigationStack(path: $coordinator.searchPath) {
                        SearchView(
                            viewModel: SearchViewModel(context: plexApiContext),
                            onSelectMedia: { displayItem in
                                switch displayItem {
                                case let .playable(media):
                                    Task {
                                        await launcher.play(ratingKey: media.id, type: media.type)
                                    }
                                case .collection:
                                    break
                                }
                            }
                        )
                        .navigationTitle("Search")
                        .navigationDestination(for: MainCoordinator.Route.self) { route in
                            destination(for: route)
                        }
                    }
                case .settings:
                    NavigationStack(path: $coordinator.settingsPath) {
                        SettingsView()
                            .navigationTitle("Settings")
                            .navigationDestination(for: MainCoordinator.Route.self) { route in
                                destination(for: route)
                            }
                    }
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 100)
            }

            // Custom Liquid Glass Tab Bar
            HStack(spacing: 12) {
                ForEach([
                    (MainCoordinator.Tab.home, "Home", "house.fill"),
                    (MainCoordinator.Tab.library, "Library", "square.grid.2x2.fill"),
                    (MainCoordinator.Tab.search, "Search", "magnifyingglass"),
                    (MainCoordinator.Tab.settings, "Settings", "gearshape.fill")
                ], id: \.1) { (tab, title, icon) in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            mainCoordinator.tab = tab
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: icon)
                                .font(.system(size: 20, weight: .bold))
                            if mainCoordinator.tab == tab {
                                Text(title)
                                    .font(.caption2.bold())
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .liquidGlassStyle()
                        .opacity(mainCoordinator.tab == tab ? 1.0 : 0.6)
                        .scaleEffect(mainCoordinator.tab == tab ? 1.1 : 1.0)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(.keyboard)
    }

    @ViewBuilder
    private func destination(for route: MainCoordinator.Route) -> some View {
        switch route {
        case let .mediaDetail(media):
            MediaDetailView(
                viewModel: MediaDetailViewModel(
                    media: media,
                    context: plexApiContext
                ),
                onPlay: { ratingKey, type in
                    Task {
                        await launcher.play(ratingKey: ratingKey, type: type)
                    }
                }
            )
        case let .collectionDetail(collection):
            CollectionDetailView(
                viewModel: CollectionDetailViewModel(
                    collection: collection,
                    context: plexApiContext
                ),
                onSelectMedia: { displayItem in
                    switch displayItem {
                    case let .playable(media):
                        Task {
                            await launcher.play(ratingKey: media.id, type: media.type)
                        }
                    case .collection:
                        break
                    }
                }
            )
        }
    }
}
