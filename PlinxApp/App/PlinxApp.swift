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
    @StateObject private var mainCoordinator = MainCoordinator()

    //── Strimr Watch-Together (inactive in Plinx; required by PlayerView's @Environment) ──
    // PlayerView reads @Environment(WatchTogetherViewModel.self). If the value
    // is absent the app crashes the first time a video is opened on iPad.
    // We inject a default idle instance so the feature is present but dormant.
    @State private var watchTogetherViewModel: WatchTogetherViewModel

    // ── Plinx Safety Layer ──────────────────────────────────────────────
    @AppStorage("plinx.maxMovieRating") private var maxMovieRatingRaw = PlinxRating.pg.rawValue
    @AppStorage("plinx.maxTVRating") private var maxTVRatingRaw = PlinxRating.tvPg.rawValue
    /// Default is `true` for kid safety: unrated items are hidden unless a
    /// parent explicitly turns this off.
    @AppStorage("plinx.excludeUnrated") private var excludeUnrated = true

    private var safetyPolicy: SafetyPolicy {
        let movieRating = PlinxRating.from(contentRating: maxMovieRatingRaw) ?? .pg
        let tvRating = PlinxRating.from(contentRating: maxTVRatingRaw) ?? .tvPg
        return SafetyPolicy.ratingOnly(maxMovie: movieRating, maxTV: tvRating, allowUnrated: !excludeUnrated)
    }

    // ── Plinx Playback / Lifecycle ──────────────────────────────────────
    @StateObject private var playbackCoordinator = PlaybackCoordinator()

    // ── Plinx Theming ───────────────────────────────────────────────────
    @State private var theme = PlinxTheme()

    // ── Plinx Safety Hardening ──────────────────────────────────────────
    @AppStorage("plinx.babyLockEnabled") private var babyLockEnabled = false

    // ── Plinx Accent Color ──────────────────────────────────────────────
    @AppStorage("plinx.accentColorName") private var accentColorName = PlinxAccentColor.green.rawValue

    private var accentColor: Color {
        PlinxAccentColor(rawValue: accentColorName)?.color ?? PlinxAccentColor.green.color
    }

    // MARK: - Init (Dependency Construction)

    init() {
        // Layer 1: Strimr infrastructure (no Plinx knowledge)
        let context = PlexAPIContext()
        let store = LibraryStore(context: context)
        let settings = SettingsManager()
        let session = SessionManager(context: context, libraryStore: store)
        _plexApiContext = State(initialValue: context)
        _sessionManager = State(initialValue: session)
        _settingsManager = State(initialValue: settings)
        _libraryStore = State(initialValue: store)

        // WatchTogether: inject an idle instance so PlayerView's @Environment lookup
        // succeeds on iPad. Plinx does not actively use Watch Together.
        _watchTogetherViewModel = State(initialValue: WatchTogetherViewModel(
            sessionManager: session,
            context: context
        ))

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
                .environmentObject(mainCoordinator)
                .environment(watchTogetherViewModel)
                // ── Plinx layer injection ───────────────────────────
                .environment(\.plinxTheme, theme)
                .environment(\.safetyPolicy, safetyPolicy)
                .environment(\.viewFactory, makeViewFactory())
                .environmentObject(playbackCoordinator)
                // ── Global configuration ────────────────────────────
                .preferredColorScheme(.dark)
                .tint(accentColor)
                .onAppear {
                    AppearanceSetup.apply(theme, accentColor: UIColor(accentColor))
                }
                .onChange(of: accentColorName) { _, _ in
                    AppearanceSetup.apply(theme, accentColor: UIColor(accentColor))
                }
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
