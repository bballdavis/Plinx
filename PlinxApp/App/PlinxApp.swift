import PlinxCore
import PlinxUI
import SwiftUI

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
//   │MainCoordinator│    │PlaybackCoordinator│
//   │ (Strimr)      │    │ (PlinxCore)       │
//   └───────────────┘    └──────────────────┘
//
// All Strimr services are @Observable and injected via SwiftUI Environment.
// Plinx-specific state (safety, theme, playback) is layered on top.
//
// ─────────────────────────────────────────────────────────────────────────────

@main
struct PlinxApp: App {
    @Environment(\.scenePhase) private var scenePhase
    #if !os(tvOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate
    #endif

    // ── Strimr Services (upstream, unmodified) ──────────────────────────
    @State private var plexApiContext: PlexAPIContext
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var libraryStore: LibraryStore
    @StateObject private var mainCoordinator = MainCoordinator()

    /// SharePlay remains available to the playback stack for dependency
    /// compatibility, while its initiation controls are hidden in kid-facing UI.
    @State private var sharePlayCoordinator: SharePlayCoordinator

    // ── Strimr DownloadManager (required by MediaDetailHeaderSection's @Environment) ──
    // MediaDetailHeaderSection reads @Environment(DownloadManager.self). Without this
    // injection the app crashes with an assertion failure when navigating to media detail.
    @State private var downloadManager: DownloadManager
    @State private var parentalAccessCoordinator: ParentalAccessCoordinator
    @State private var downloadOwnershipStore: DownloadOwnershipStore
    @State private var sessionAccessCoordinator: PlinxSessionAccessCoordinator

    // ── Plinx Safety Layer ──────────────────────────────────────────────
    @AppStorage("plinx.maxMovieRating") private var maxMovieRatingRaw = PlinxRating.g.rawValue
    @AppStorage("plinx.maxTVRating") private var maxTVRatingRaw = PlinxRating.tvY.rawValue
    /// Default is `true` for kid safety: unrated items are hidden unless a
    /// parent explicitly turns this off.
    @AppStorage("plinx.excludeUnrated") private var excludeUnrated = true

    @AppStorage("plinx.maxMovieRating", store: DemoPreferences.defaults) private var demoMovieRatingRaw = PlinxRating.pg.rawValue
    @AppStorage("plinx.maxTVRating", store: DemoPreferences.defaults) private var demoTVRatingRaw = PlinxRating.tvPg.rawValue
    @AppStorage("plinx.excludeUnrated", store: DemoPreferences.defaults) private var demoExcludeUnrated = true
    #if !os(tvOS)
    @AppStorage("plinx.babyLockEnabled", store: DemoPreferences.defaults) private var demoBabyLockEnabled = false
    #endif

    private var isDemoSession: Bool {
        DemoFixtureBootstrap.isActive && sessionManager.plexServer?.clientIdentifier == DemoFixtureBootstrap.serverIdentifier
    }

    private var safetyPolicy: SafetyPolicy {
        let movieRating = PlinxRating.from(contentRating: isDemoSession ? demoMovieRatingRaw : maxMovieRatingRaw) ?? .g
        let tvRating = PlinxRating.from(contentRating: isDemoSession ? demoTVRatingRaw : maxTVRatingRaw) ?? .tvY
        return SafetyPolicy.ratingOnly(maxMovie: movieRating, maxTV: tvRating, allowUnrated: !(isDemoSession ? demoExcludeUnrated : excludeUnrated))
    }

    /// ── Plinx Playback / Lifecycle ──────────────────────────────────────
    @StateObject private var playbackCoordinator = PlaybackCoordinator()

    /// ── Plinx Theming ───────────────────────────────────────────────────
    @State private var theme = PlinxTheme()

    // ── Plinx Safety Hardening ──────────────────────────────────────────
    #if !os(tvOS)
    @AppStorage("plinx.babyLockEnabled") private var babyLockEnabled = false
    #endif

    /// ── Plinx Accent Color ──────────────────────────────────────────────
    @AppStorage("plinx.accentColorName") private var accentColorName = PlinxAccentColor.green.rawValue

    private var accentColor: Color {
        PlinxAccentColor(rawValue: accentColorName)?.color ?? PlinxAccentColor.green.color
    }

    // MARK: - Init (Dependency Construction)

    init() {
        let processEnvironment = ProcessInfo.processInfo.environment
        ReleaseScreenshotCaptureMode.installNetworkMutationBlockerIfNeeded()
        LivePlexUITestBootstrap.primeCredentialsIfNeeded(environment: processEnvironment)

        // Layer 1: Strimr infrastructure (no Plinx knowledge)
        let context = PlexAPIContext()
        let store = LibraryStore(context: context)
        let settings = SettingsManager()
        PlinxSettingsSanitizer.applyPlinxDefaults(settings)
        PlinxSettingsSanitizer.disableUnsupportedExternalDiscovery(settings)
        let session = SessionManager(context: context, libraryStore: store)
        _plexApiContext = State(initialValue: context)
        _sessionManager = State(initialValue: session)
        _settingsManager = State(initialValue: settings)
        _libraryStore = State(initialValue: store)

        _sharePlayCoordinator = State(initialValue: SharePlayCoordinator(
            sessionManager: session,
            context: context
        ))

        // DownloadManager: inject so MediaDetailHeaderSection's @Environment(DownloadManager.self)
        // resolves. Plinx supports downloads as a passthrough from Strimr.
        #if !os(tvOS)
        DownloadUITestFixtures.seedIfNeeded(environment: processEnvironment)
        #endif
        let downloads = DownloadManager(settingsManager: settings)
        LivePlexUITestBootstrap.bootstrapIfNeeded(
            environment: processEnvironment,
            sessionManager: session,
            context: context
        )
        _downloadManager = State(initialValue: downloads)
        _parentalAccessCoordinator = State(initialValue: ParentalAccessCoordinator())
        _downloadOwnershipStore = State(
            initialValue: DownloadOwnershipStore(
                existingDownloadItems: downloads.items,
                canMigrateExistingDownloads: downloads.persistedIndexState.permitsOwnershipMigration
            )
        )
        _sessionAccessCoordinator = State(initialValue: PlinxSessionAccessCoordinator())

        // Layer 2: Plinx safety + theming are initialized via property defaults.
    }

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            PlinxContentView()
                .defaultAppStorage(isDemoSession ? DemoPreferences.defaults : .standard)
                // ── Strimr service injection ────────────────────────
                .environment(plexApiContext)
                .environment(sessionManager)
                .environment(isDemoSession ? DemoPreferences.settings : settingsManager)
                .environment(libraryStore)
                .environmentObject(mainCoordinator)
                .environment(sharePlayCoordinator)
                .environment(downloadManager)
                .environment(isDemoSession ? DemoPreferences.parentalAccess : parentalAccessCoordinator)
                .environment(downloadOwnershipStore)
                .environment(sessionAccessCoordinator)
                .environment(\.sharePlayPresentationPolicy, .hidden)
                // ── Plinx layer injection ───────────────────────────
                .environment(\.plinxTheme, theme)
                .environment(\.safetyPolicy, safetyPolicy)
                .environmentObject(playbackCoordinator)
                // ── Global configuration ────────────────────────────
                .preferredColorScheme(.dark)
                .fontDesign(.rounded)
                .tint(accentColor)
                .progressViewStyle(PlinxProgressViewStyle())
                .onAppear {
                    AppearanceSetup.apply(theme, accentColor: UIColor(accentColor))
                }
                .onChange(of: accentColorName) { _, _ in
                    AppearanceSetup.apply(theme, accentColor: UIColor(accentColor))
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase != .active {
                        parentalAccessCoordinator.lock()
                        DemoPreferences.parentalAccess.lock()
                    }
                }
            // ── Lifecycle hardening ─────────────────────────────
            #if !os(tvOS)
                .lifecycleHardening(
                    coordinator: playbackCoordinator,
                    mainCoordinator: mainCoordinator,
                    downloadManager: downloadManager,
                    plexApiContext: plexApiContext,
                    sessionManager: sessionManager,
                    sessionAccessCoordinator: sessionAccessCoordinator,
                    downloadOwnershipStore: downloadOwnershipStore
                )
            #else
                .lifecycleHardening(
                    coordinator: playbackCoordinator,
                    mainCoordinator: mainCoordinator
                )
            #endif
            #if !os(tvOS)
            // ── Touch-only baby lock overlay ───────────────────
                .babyLock(isEnabled: isDemoSession ? $demoBabyLockEnabled : $babyLockEnabled)
            #endif
        }
    }
}
