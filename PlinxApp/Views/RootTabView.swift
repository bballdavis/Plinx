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

    private var launcher: PlaybackLauncher {
        PlaybackLauncher(
            context: plexApiContext,
            coordinator: mainCoordinator,
            settingsManager: settingsManager,
            openURL: { url in openURL(url) }
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            Group {
                switch mainCoordinator.tab {
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
                            onSelectMedia: { displayItem in
                                switch displayItem {
                                case let .playable(media):
                                    Task { await launcher.play(ratingKey: media.id, type: media.type) }
                                case let .collection(collection):
                                    mainCoordinator.showCollectionDetail(collection)
                                }
                            }
                        )
                        .navigationTitle("Home")
                        .navigationDestination(for: MainCoordinator.Route.self) { route in
                            destination(for: route)
                        }
                    }

                case .library:
                    NavigationStack(path: mainCoordinator.pathBinding(for: .library)) {
                        PlinxLibraryView(
                            viewModel: SafeLibraryViewModel(
                                inner: LibraryViewModel(
                                    context: plexApiContext,
                                    libraryStore: libraryStore
                                ),
                                policy: safetyPolicy
                            ),
                            onSelectLibrary: { library in
                                mainCoordinator.libraryPath.append(library)
                            }
                        )
                        .navigationTitle("Library")
                        .navigationDestination(for: Library.self) { library in
                            LibraryDetailView(
                                library: library,
                                onSelectMedia: { displayItem in
                                    switch displayItem {
                                    case let .playable(media):
                                        Task { await launcher.play(ratingKey: media.id, type: media.type) }
                                    case let .collection(collection):
                                        mainCoordinator.showCollectionDetail(collection)
                                    }
                                }
                            )
                        }
                        .navigationDestination(for: MainCoordinator.Route.self) { route in
                            destination(for: route)
                        }
                    }

                case .search:
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
                                }
                            }
                        )
                        .navigationTitle("Search")
                        .navigationDestination(for: MainCoordinator.Route.self) { route in
                            destination(for: route)
                        }
                    }

                case .more:
                    NavigationStack(path: mainCoordinator.pathBinding(for: .more)) {
                        PlinxSettingsView()
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
                    (MainCoordinator.Tab.more, "Settings", "gearshape.fill")
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
        }
    }
}
