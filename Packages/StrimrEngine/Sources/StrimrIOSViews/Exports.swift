// ─────────────────────────────────────────────────────────────────────────────
// StrimrIOSViews/Exports.swift
// ─────────────────────────────────────────────────────────────────────────────
//
// Companion to StrimrEngine/Exports.swift for the iOS-specific view layer.
// This target wraps the sibling Strimr checkout's Strimr-iOS/Features tree —
// that Plinx progressively replaces with Liquid Glass equivalents.
//
// Once all views in the Progressive Replacement Schedule are done (Phase 6),
// this entire target can be removed from the dependency graph.
//
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public enum StrimrIOSViewsExports {
    public static let version = "0.1.0"

    /// Views that Plinx has replaced with its own implementations.
    /// When this list matches ALL Strimr iOS views, this target can be deleted.
    public static let replacedViews: [String] = [
        "MainTabView     → RootTabView (P0 ✅)",
        "ContentView     → PlinxContentView (P0 ✅)",
        "HomeView        → PlinxHomeView (P0 ✅)",
        "PlayerWrapper   → PlinxPlayerView (P0 ✅)",
        "LibraryView     → PlinxLibraryView (P1 ✅)",
        "SearchView      → PlinxSearchView (P1 ✅)",
        "MediaDetailView → PlinxMediaDetailView (P2 ✅)",
        "CollectionDetailView → PlinxCollectionDetailView (P2 ✅)",
        "SettingsView    → PlinxSettingsView (P3 ✅)",
        // Remaining (not yet replaced):
        // "SignInView         → PlinxSignInView (P3)",
        // "ProfileSwitcherView → PlinxProfileView (P3)",
        // "SelectServerView   → PlinxServerView (P3)",
    ]
}
