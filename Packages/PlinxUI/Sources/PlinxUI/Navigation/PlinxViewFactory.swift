import SwiftUI
import PlinxCore

// ─────────────────────────────────────────────────────────────────────────────
// PlinxViewFactory — View Resolution Protocol
// ─────────────────────────────────────────────────────────────────────────────
//
// The ViewFactory pattern decouples Plinx's navigation shell (RootTabView,
// PlinxContentView) from the concrete views and view models they present.
//
// PlinxViewFactory is defined in PlinxUI with NO Strimr type dependencies.
// The concrete implementation lives in PlinxApp where Strimr's internal types
// are accessible. This keeps PlinxUI a pure presentation module.
//
// Data flow:
//   PlinxApp creates PlinxViewFactoryImpl (concrete, knows Strimr types)
//     → injected into RootTabView via environment
//       → RootTabView calls factory.makeHomeView(), factory.makeLibraryView()...
//         → factory creates Safe*ViewModel decorator + Plinx-themed view
//           → view observes decorated (filtered) data only
//
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Protocol

/// Resolves Plinx views. Implemented by `PlinxViewFactoryImpl` in PlinxApp.
///
/// Every `make*` method returns an opaque `some View` so the factory can
/// compose any combination of decorator + view without leaking concrete types.
///
/// The `onSelectMedia` callbacks use `PlinxMediaAction` (a PlinxUI-safe type)
/// to communicate user selections back to the navigation layer.
@MainActor
public protocol PlinxViewFactory: Sendable {

    /// Creates the home screen (continue-watching + recently-added hubs).
    func makeHomeView(onSelectMedia: @escaping (PlinxMediaAction) -> Void) -> AnyView

    /// Creates the library grid (list of Plex libraries).
    func makeLibraryView(onSelectLibrary: @escaping (String) -> Void) -> AnyView

    /// Creates the search screen.
    func makeSearchView(onSelectMedia: @escaping (PlinxMediaAction) -> Void) -> AnyView

    /// Creates the settings screen (behind parental gate).
    func makeSettingsView() -> AnyView

    /// Creates the media detail screen for a given media ID.
    func makeMediaDetailView(
        mediaID: String,
        onPlay: @escaping (String, String) -> Void,
        onSelectRelated: @escaping (PlinxMediaAction) -> Void
    ) -> AnyView

    /// Creates the collection detail screen for a given collection ID.
    func makeCollectionDetailView(
        collectionID: String,
        onSelectMedia: @escaping (PlinxMediaAction) -> Void
    ) -> AnyView
}

// MARK: - Media Action

/// A navigation-safe representation of a user selection on a media item.
/// This type lives in PlinxUI (no Strimr dependency) so the ViewFactory
/// protocol can use it across module boundaries.
public enum PlinxMediaAction: Sendable {
    /// User tapped a playable item (movie, episode).
    case play(id: String, type: String)
    /// User tapped a collection (show, collection).
    case browseCollection(id: String, title: String)
    /// User tapped a playlist.
    case browsePlaylist(id: String, title: String)
}

// MARK: - Environment Key

private struct ViewFactoryKey: EnvironmentKey {
    // Default is nil — must be injected at composition root.
    static let defaultValue: (any PlinxViewFactory)? = nil
}

public extension EnvironmentValues {
    var viewFactory: (any PlinxViewFactory)? {
        get { self[ViewFactoryKey.self] }
        set { self[ViewFactoryKey.self] = newValue }
    }
}
