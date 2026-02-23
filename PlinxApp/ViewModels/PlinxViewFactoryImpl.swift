import SwiftUI
import PlinxCore
import PlinxUI

// ─────────────────────────────────────────────────────────────────────────────
// PlinxViewFactoryImpl — Concrete View Factory
// ─────────────────────────────────────────────────────────────────────────────
//
// This is the composition bridge: it has access to both Strimr's internal types
// (compiled into the app module) and Plinx's public types (via PlinxCore/PlinxUI).
//
// For each `make*` method:
//   1. Create the Strimr view model (using Strimr's internal constructors)
//   2. Wrap it in a Safe*ViewModel decorator (applies SafetyPolicy filtering)
//   3. Create the Plinx-themed SwiftUI view (from PlinxUI or Views/)
//   4. Return as AnyView (type-erased for protocol conformance)
//
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class PlinxViewFactoryImpl: PlinxViewFactory {

    // MARK: - Dependencies (injected from composition root)

    private let plexApiContext: PlexAPIContext
    private let sessionManager: SessionManager
    private let settingsManager: SettingsManager
    private let libraryStore: LibraryStore
    private let mainCoordinator: MainCoordinator
    private let safetyPolicy: SafetyPolicy

    init(
        plexApiContext: PlexAPIContext,
        sessionManager: SessionManager,
        settingsManager: SettingsManager,
        libraryStore: LibraryStore,
        mainCoordinator: MainCoordinator,
        safetyPolicy: SafetyPolicy
    ) {
        self.plexApiContext = plexApiContext
        self.sessionManager = sessionManager
        self.settingsManager = settingsManager
        self.libraryStore = libraryStore
        self.mainCoordinator = mainCoordinator
        self.safetyPolicy = safetyPolicy
    }

    // MARK: - Factory Methods

    func makeHomeView(onSelectMedia: @escaping (PlinxMediaAction) -> Void) -> AnyView {
        let inner = HomeViewModel(
            context: plexApiContext,
            settingsManager: settingsManager,
            libraryStore: libraryStore
        )
        let safe = SafeHomeViewModel(inner: inner, policy: safetyPolicy)
        return AnyView(
            PlinxHomeView(viewModel: safe) { displayItem in
                onSelectMedia(displayItem.toPlinxAction())
            }
        )
    }

    func makeLibraryView(onSelectLibrary: @escaping (String) -> Void) -> AnyView {
        let inner = LibraryViewModel(
            context: plexApiContext,
            libraryStore: libraryStore
        )
        let safe = SafeLibraryViewModel(inner: inner, policy: safetyPolicy, context: plexApiContext)
        return AnyView(
            PlinxLibraryView(viewModel: safe) { library in
                onSelectLibrary(library.id)
            }
        )
    }

    func makeSearchView(onSelectMedia: @escaping (PlinxMediaAction) -> Void) -> AnyView {
        let inner = SearchViewModel(context: plexApiContext)
        let safe = SafeSearchViewModel(inner: inner, policy: safetyPolicy)
        return AnyView(
            PlinxSearchView(viewModel: safe) { displayItem in
                onSelectMedia(displayItem.toPlinxAction())
            }
        )
    }

    func makeSettingsView() -> AnyView {
        AnyView(PlinxSettingsView())
    }

    func makeMediaDetailView(
        mediaID: String,
        onPlay: @escaping (String, String) -> Void,
        onSelectRelated: @escaping (PlinxMediaAction) -> Void
    ) -> AnyView {
        // Note: MediaDetailViewModel requires a PlayableMediaItem to construct.
        // In practice, the RootTabView constructs this directly using the
        // Strimr type from navigation state. This factory method provides
        // the pattern for future use when we can resolve by ID.
        AnyView(
            Text("Media Detail: \(mediaID)")
                .foregroundStyle(.secondary)
        )
    }

    func makeCollectionDetailView(
        collectionID: String,
        onSelectMedia: @escaping (PlinxMediaAction) -> Void
    ) -> AnyView {
        // Same note as makeMediaDetailView — collection resolution by ID
        // requires navigation state that RootTabView manages directly.
        AnyView(
            Text("Collection: \(collectionID)")
                .foregroundStyle(.secondary)
        )
    }
}

// MARK: - MediaDisplayItem → PlinxMediaAction Bridge

/// Extension on Strimr's `MediaDisplayItem` to convert to PlinxUI's
/// navigation-safe `PlinxMediaAction`. This lives in the app target
/// because `MediaDisplayItem` is an internal Strimr type.
extension MediaDisplayItem {
    func toPlinxAction() -> PlinxMediaAction {
        switch self {
        case let .playable(item):
            return .play(id: item.id, type: item.type.rawValue)
        case let .collection(collection):
            return .browseCollection(id: collection.id, title: collection.title)
        case let .playlist(playlist):
            return .play(id: playlist.id, type: playlist.type.rawValue)
        }
    }
}
