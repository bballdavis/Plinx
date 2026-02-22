import SwiftUI
import PlinxCore
import PlinxUI

#if canImport(UIKit)
import UIKit
#endif

// ─────────────────────────────────────────────────────────────────────────────
// PlinxApp — Composition Root
// ─────────────────────────────────────────────────────────────────────────────
//
// This is the single point where Strimr services, Plinx safety layer, theming,
// and lifecycle management are wired together.
//
// Dependency Injection Flow:
//
//   ┌─────────────┐     ┌──────────────┐     ┌────────────┐
//   │ PlexAPIContext│────▶│SessionManager│     │ PlinxTheme │
//   │ (Strimr)     │     │ (Strimr)     │     │ (PlinxUI)  │
//   └──────┬───────┘     └──────────────┘     └────────────┘
//          │
//   ┌──────┴───────┐     ┌──────────────┐     ┌──────────────┐
//   │ LibraryStore  │     │SettingsManager│    │ SafetyPolicy │
//   │ (Strimr)      │     │ (Strimr)     │    │ (PlinxCore)  │
//   └───────────────┘     └──────────────┘    └──────┬───────┘
//                                                     │
//   ┌──────────────┐     ┌──────────────────┐  ┌─────┴────────┐
//   │MainCoordinator│    │PlaybackCoordinator│  │ViewFactory   │
//   │ (Strimr)      │    │ (PlinxCore)       │  │(PlinxApp)    │
//   └───────────────┘    └──────────────────┘  └──────────────┘
//
// All Strimr services are @Observable and injected via SwiftUI Environment.
// Plinx-specific state (safety, theme, playback) is layered on top.
// The ViewFactory bridges between Strimr internals and Plinx views.
//
// ─────────────────────────────────────────────────────────────────────────────

@main
struct PlinxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate

    // ── Strimr Services (upstream, unmodified) ──────────────────────────
    @State private var plexApiContext: PlexAPIContext
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var libraryStore: LibraryStore
    @State private var mainCoordinator: MainCoordinator

    // ── Plinx Safety Layer ──────────────────────────────────────────────
    @State private var safetyPolicy = SafetyPolicy.ratingOnly()

    // ── Plinx Playback / Lifecycle ──────────────────────────────────────
    @StateObject private var playbackCoordinator = PlaybackCoordinator()

    // ── Plinx Theming ───────────────────────────────────────────────────
    @State private var theme = PlinxTheme()

    // ── Plinx Safety Hardening ──────────────────────────────────────────
    @AppStorage("plinx.babyLockEnabled") private var babyLockEnabled = false

    // MARK: - Init (Dependency Construction)

    init() {
        // Layer 1: Strimr infrastructure (no Plinx knowledge)
        let context = PlexAPIContext()
        let store = LibraryStore(context: context)
        let settings = SettingsManager()
        let session = SessionManager(context: context, libraryStore: store)
        let coordinator = MainCoordinator()

        _plexApiContext = State(initialValue: context)
        _sessionManager = State(initialValue: session)
        _settingsManager = State(initialValue: settings)
        _libraryStore = State(initialValue: store)
        _mainCoordinator = State(initialValue: coordinator)

        // Layer 2: Plinx safety + theming are initialized via property defaults.
        // The ViewFactory is created in `body` since it needs the live state refs.
    }

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            PlinxContentView()
                // ── Strimr service injection ────────────────────────
                .environment(plexApiContext)
                .environment(sessionManager)
                .environment(settingsManager)
                .environment(libraryStore)
                .environment(mainCoordinator)
                // ── Plinx layer injection ───────────────────────────
                .environment(\.plinxTheme, theme)
                .environment(\.safetyPolicy, safetyPolicy)
                .environment(\.viewFactory, makeViewFactory())
                .environmentObject(playbackCoordinator)
                // ── Global configuration ────────────────────────────
                .preferredColorScheme(.dark)
                .onAppear { AppearanceSetup.apply(theme) }
                // ── Lifecycle hardening ─────────────────────────────
                .lifecycleHardening(
                    coordinator: playbackCoordinator,
                    mainCoordinator: mainCoordinator
                )
                // ── Baby lock overlay ───────────────────────────────
                .babyLock(isEnabled: $babyLockEnabled)
        }
    }

    // MARK: - Factory Construction

    /// Creates the ViewFactory with all current service references.
    /// Called each time the scene body is re-evaluated (which is fine —
    /// the factory is a lightweight value holder).
    @MainActor
    private func makeViewFactory() -> PlinxViewFactoryImpl {
        PlinxViewFactoryImpl(
            plexApiContext: plexApiContext,
            sessionManager: sessionManager,
            settingsManager: settingsManager,
            libraryStore: libraryStore,
            mainCoordinator: mainCoordinator,
            safetyPolicy: safetyPolicy
        )
    }
}
