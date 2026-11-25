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
// The single point where the absorbed media stack (Core + Platform), the Plinx
// safety boundary, theming and lifecycle hardening are wired together.
//
//   SettingsManager ─┬─▶ TrackSelectionCoordinator ─┐
//   FavoritesStore ──┴──────────────────────────────┴─▶ SessionManager
//                                                          │ registry (ServerRegistry)
//                                                          │   └─ every MediaServices is wrapped in
//                                                          │      SafeMediaServices (ContentSafetyGate)
//   LibraryStore, SeerrStore, SharePlayCoordinator ◀───────┤
//   DownloadManager, OfflineCoordinator (iOS only)          │
//   MainCoordinator (navigation + player presentation)      │
//
// Plinx state layered on top: ParentalAccessCoordinator, PlinxWatchStatusStore,
// PlaybackLaunchCoordinator, PlaybackCoordinator, PlinxTheme and the computed
// SafetyPolicy. Screens get services from `ServerRegistry` or use the shared
// view models initialised with `SessionManager`/`SettingsManager`.
//
// The SafetyPolicy computed here is pushed into `ContentSafetyGate.shared`
// before any session hydrates, and kept in sync with the parental gate.
// ─────────────────────────────────────────────────────────────────────────────

@main
struct PlinxApp: App {
    @Environment(\.scenePhase) private var scenePhase
    #if !os(tvOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate
    #endif

    // ── Media stack ─────────────────────────────────────────────────────
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var libraryStore: LibraryStore
    @State private var seerrStore: SeerrStore
    /// SharePlay stays available to the playback stack; its initiation
    /// controls are hidden in kid-facing UI (`sharePlayPresentationPolicy`).
    @State private var sharePlayCoordinator: SharePlayCoordinator
    @StateObject private var mainCoordinator: MainCoordinator
    #if !os(tvOS)
    @State private var downloadManager: DownloadManager
    #endif

    // ── Plinx layer ─────────────────────────────────────────────────────
    @State private var parentalAccessCoordinator = ParentalAccessCoordinator()
    @State private var watchStatusStore = PlinxWatchStatusStore()
    @StateObject private var playbackLaunchCoordinator = PlaybackLaunchCoordinator()
    @StateObject private var playbackCoordinator = PlaybackCoordinator()
    @State private var theme = PlinxTheme()

    // ── Safety preferences ──────────────────────────────────────────────
    @AppStorage(PlinxSafetyPreferences.maxMovieRatingKey)
    private var maxMovieRatingRaw = PlinxSafetyPreferences.defaultMovieRating.rawValue
    @AppStorage(PlinxSafetyPreferences.maxTVRatingKey)
    private var maxTVRatingRaw = PlinxSafetyPreferences.defaultTVRating.rawValue
    /// Default is `true` for kid safety: unrated items are hidden unless a
    /// parent explicitly turns this off.
    @AppStorage(PlinxSafetyPreferences.excludeUnratedKey)
    private var excludeUnrated = true

    @AppStorage(PlinxSafetyPreferences.maxMovieRatingKey, store: DemoPreferences.defaults)
    private var demoMovieRatingRaw = PlinxRating.pg.rawValue
    @AppStorage(PlinxSafetyPreferences.maxTVRatingKey, store: DemoPreferences.defaults)
    private var demoTVRatingRaw = PlinxRating.tvPg.rawValue
    @AppStorage(PlinxSafetyPreferences.excludeUnratedKey, store: DemoPreferences.defaults)
    private var demoExcludeUnrated = true

    // ── Plinx safety hardening and accent ───────────────────────────────
    #if !os(tvOS)
    @AppStorage("plinx.babyLockEnabled") private var babyLockEnabled = false
    @AppStorage("plinx.babyLockEnabled", store: DemoPreferences.defaults) private var demoBabyLockEnabled = false
    #endif
    @AppStorage("plinx.accentColorName") private var accentColorName = PlinxAccentColor.green.rawValue

    private var accentColor: Color {
        PlinxAccentColor(rawValue: accentColorName)?.color ?? PlinxAccentColor.green.color
    }

    /// The App Review sample library runs with its own preferences and PIN.
    private var isDemoSession: Bool {
        DemoFixtureBootstrap.isDemoSession(sessionManager)
    }

    private var safetyPolicy: SafetyPolicy {
        if isDemoSession {
            return PlinxSafetyPreferences.policy(
                maxMovieRating: demoMovieRatingRaw,
                maxTVRating: demoTVRatingRaw,
                excludeUnrated: demoExcludeUnrated
            )
        }
        return PlinxSafetyPreferences.policy(
            maxMovieRating: maxMovieRatingRaw,
            maxTVRating: maxTVRatingRaw,
            excludeUnrated: excludeUnrated
        )
    }

    private var effectiveParentalAccess: ParentalAccessCoordinator {
        isDemoSession ? DemoPreferences.parentalAccess : parentalAccessCoordinator
    }

    // MARK: - Init (dependency construction)

    init() {
        let processEnvironment = ProcessInfo.processInfo.environment
        ReleaseScreenshotCaptureMode.installNetworkMutationBlockerIfNeeded()
        LivePlexUITestBootstrap.primeCredentialsIfNeeded(environment: processEnvironment)

        // Fail closed from the first request: the boundary carries the stored
        // family policy before any session hydrates or any screen loads.
        ContentSafetyGate.shared.policy = PlinxSafetyPreferences.storedPolicy()

        let favoritesStore = FavoritesStore()
        let settings = SettingsManager()
        PlinxSettingsSanitizer.applyPlinxDefaults(settings)
        PlinxSettingsSanitizer.disableUnsupportedFeatures(settings)

        let trackSelectionCoordinator = TrackSelectionCoordinator(
            store: TrackSelectionStore(),
            settingsManager: settings
        )
        let session = SessionManager(
            settingsManager: settings,
            favoritesStore: favoritesStore,
            trackSelectionCoordinator: trackSelectionCoordinator,
            versionSelectionStore: MediaVersionSelectionStore()
        )

        _sessionManager = State(initialValue: session)
        _settingsManager = State(initialValue: settings)
        _libraryStore = State(initialValue: LibraryStore(sessionManager: session, settingsManager: settings))
        _seerrStore = State(initialValue: SeerrStore())
        _sharePlayCoordinator = State(initialValue: SharePlayCoordinator(sessionManager: session))
        _mainCoordinator = StateObject(wrappedValue: MainCoordinator(settingsManager: settings))

        #if !os(tvOS)
        DownloadUITestFixtures.seedIfNeeded(environment: processEnvironment)
        _downloadManager = State(initialValue: DownloadManager(settingsManager: settings))
        #endif

        LivePlexUITestBootstrap.bootstrapIfNeeded(environment: processEnvironment, sessionManager: session)
        DemoFixtureBootstrap.bootstrapForUITestIfNeeded(environment: processEnvironment, sessionManager: session)
    }

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            PlinxContentView()
                .defaultAppStorage(isDemoSession ? DemoPreferences.defaults : .standard)
                // ── Media stack ─────────────────────────────────────
                .environment(sessionManager)
                .environment(sessionManager.registry)
                .environment(isDemoSession ? DemoPreferences.settings : settingsManager)
                .environment(libraryStore)
                .environment(seerrStore)
                .environment(sharePlayCoordinator)
                .environmentObject(mainCoordinator)
            #if !os(tvOS)
                .environment(downloadManager)
                .environment(OfflineCoordinator.shared)
            #endif
                // ── Plinx layer ─────────────────────────────────────
                .environment(effectiveParentalAccess)
                .environment(watchStatusStore)
                .environmentObject(playbackLaunchCoordinator)
                .environmentObject(playbackCoordinator)
                .environment(\.sharePlayPresentationPolicy, .hidden)
                .environment(\.plinxTheme, theme)
                .environment(\.safetyPolicy, safetyPolicy)
                .modifier(ContentSafetyBoundarySync(policy: safetyPolicy, parentalAccess: effectiveParentalAccess))
                // ── Global configuration ────────────────────────────
                .toastHost()
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
                    // Protected UI never survives leaving the foreground.
                    if newPhase != .active {
                        parentalAccessCoordinator.lock()
                        DemoPreferences.parentalAccess.lock()
                    }
                }
                // ── Lifecycle hardening ─────────────────────────────
                .lifecycleHardening(
                    coordinator: playbackCoordinator,
                    mainCoordinator: mainCoordinator
                )
            #if !os(tvOS)
                // ── Touch-only baby lock overlay ───────────────────
                .babyLock(isEnabled: isDemoSession ? $demoBabyLockEnabled : $babyLockEnabled)
            #endif
        }
    }
}

// MARK: - Safety preferences

/// Parent-controlled ceilings stored in `UserDefaults`. Missing or unknown
/// values fall back to the strictest defaults (G, TV-Y, unrated hidden).
enum PlinxSafetyPreferences {
    static let maxMovieRatingKey = "plinx.maxMovieRating"
    static let maxTVRatingKey = "plinx.maxTVRating"
    static let excludeUnratedKey = "plinx.excludeUnrated"
    static let defaultMovieRating = PlinxRating.g
    static let defaultTVRating = PlinxRating.tvY

    static func policy(maxMovieRating: String, maxTVRating: String, excludeUnrated: Bool) -> SafetyPolicy {
        SafetyPolicy.ratingOnly(
            maxMovie: PlinxRating.from(contentRating: maxMovieRating) ?? defaultMovieRating,
            maxTV: PlinxRating.from(contentRating: maxTVRating) ?? defaultTVRating,
            allowUnrated: !excludeUnrated
        )
    }

    /// The family policy as persisted, read before SwiftUI property wrappers exist.
    static func storedPolicy(defaults: UserDefaults = .standard) -> SafetyPolicy {
        policy(
            maxMovieRating: defaults.string(forKey: maxMovieRatingKey) ?? defaultMovieRating.rawValue,
            maxTVRating: defaults.string(forKey: maxTVRatingKey) ?? defaultTVRating.rawValue,
            excludeUnrated: defaults.object(forKey: excludeUnratedKey) as? Bool ?? true
        )
    }
}

// MARK: - Safety boundary synchronisation

/// Keeps `ContentSafetyGate.shared` equal to the policy the app computes and
/// to the effective parental gate (the demo has its own coordinator).
private struct ContentSafetyBoundarySync: ViewModifier {
    let policy: SafetyPolicy
    let parentalAccess: ParentalAccessCoordinator

    func body(content: Content) -> some View {
        content
            .onAppear(perform: synchronize)
            .onChange(of: policy) { _, _ in synchronize() }
            .onChange(of: parentalAccess.isUnlocked) { _, _ in synchronize() }
            .onChange(of: ObjectIdentifier(parentalAccess)) { _, _ in synchronize() }
    }

    private func synchronize() {
        let gate = ContentSafetyGate.shared
        if gate.policy != policy {
            gate.policy = policy
        }
        if gate.isParentUnlocked != parentalAccess.isUnlocked {
            gate.isParentUnlocked = parentalAccess.isUnlocked
        }
    }
}
