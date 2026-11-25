import Observation
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
// before any session hydrates. `ContentSafetyBoundary` then keeps the gate
// equal to that policy and to the effective parental gate, and
// `ParentalSceneLock` relocks the parental gate when the app leaves the
// foreground.
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
    @State private var parentalAccessCoordinator: ParentalAccessCoordinator
    @State private var parentalSceneLock: ParentalSceneLock
    @State private var safetyBoundary: ContentSafetyBoundary
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
        let familyParentalAccess = ParentalAccessCoordinator()
        _parentalAccessCoordinator = State(initialValue: familyParentalAccess)
        _parentalSceneLock = State(initialValue: ParentalSceneLock(deferral: .shared, lock: {
            familyParentalAccess.lock()
            DemoPreferences.parentalAccess.lock()
        }))
        _safetyBoundary = State(initialValue: ContentSafetyBoundary(gate: .shared))

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
                .modifier(ContentSafetyBoundarySync(
                    boundary: safetyBoundary,
                    policy: safetyPolicy,
                    parentalAccess: effectiveParentalAccess
                ))
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
                    // Protected UI never survives leaving the foreground; an
                    // account sign-in in progress defers it, bounded.
                    parentalSceneLock.scenePhaseChanged(to: newPhase)
                }
                // ── Lifecycle hardening ─────────────────────────────
                .lifecycleHardening(
                    coordinator: playbackCoordinator,
                    mainCoordinator: mainCoordinator,
                    settingsManager: isDemoSession ? DemoPreferences.settings : settingsManager
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

/// Keeps `ContentSafetyGate` equal to the policy the app computes and to the
/// effective parental gate (the sample library has its own coordinator).
///
/// Parent-only abilities behind the boundary (server rights, management,
/// deletion, playlist edits, subtitle downloads) read
/// `ContentSafetyGate.isParentUnlocked`, so a relock must reach the gate
/// whatever locked the coordinator, whether or not a view updates. The
/// boundary observes the coordinator itself: when an unlocked coordinator is
/// about to change, the gate closes at once, before the coordinator stores its
/// new state, and the new state is copied on the next main-actor turn. The
/// gate only opens while that observation is armed, and a coordinator that
/// stays locked never writes to the gate.
@MainActor
final class ContentSafetyBoundary {
    let gate: ContentSafetyGate
    /// The coordinator the gate follows; `nil` until the first `update`, when the gate stays locked.
    private(set) var parentalAccess: ParentalAccessCoordinator?
    /// Bumped for every observation, so a callback armed earlier or for a replaced coordinator does nothing.
    private var generation = 0
    /// Whether a change of `parentalAccess` will reach `coordinatorWillChange`; observation fires once.
    private var isObserving = false

    init(gate: ContentSafetyGate) {
        self.gate = gate
    }

    /// Applies `policy` and makes the gate follow `parentalAccess` from now on, in place of any previous coordinator.
    func update(policy: SafetyPolicy, parentalAccess: ParentalAccessCoordinator) {
        if gate.policy != policy {
            gate.policy = policy
        }
        if self.parentalAccess !== parentalAccess {
            self.parentalAccess = parentalAccess
            observe(parentalAccess)
        }
        synchronizeParentAccess()
    }

    private func synchronizeParentAccess() {
        guard let parentalAccess else {
            if gate.isParentUnlocked {
                gate.isParentUnlocked = false
            }
            return
        }
        if !isObserving {
            // Never open the gate without following the coordinator's next change.
            observe(parentalAccess)
        }
        if gate.isParentUnlocked != parentalAccess.isUnlocked {
            gate.isParentUnlocked = parentalAccess.isUnlocked
        }
    }

    private func observe(_ coordinator: ParentalAccessCoordinator) {
        generation += 1
        let generation = generation
        let wasUnlocked = coordinator.isUnlocked
        isObserving = true
        withObservationTracking {
            _ = coordinator.isUnlocked
        } onChange: { [weak self] in
            // Called on the main actor (the coordinator is main-actor isolated), before the change is stored.
            MainActor.assumeIsolated {
                self?.coordinatorWillChange(generation: generation, wasUnlocked: wasUnlocked)
            }
        }
    }

    private func coordinatorWillChange(generation: Int, wasUnlocked: Bool) {
        guard generation == self.generation else { return }
        isObserving = false
        if wasUnlocked {
            // Fail closed: a parent session that may be ending grants nothing from now on.
            gate.isParentUnlocked = false
        }
        Task { @MainActor [weak self] in
            // A newer observation (a synchronization or another coordinator) has taken over.
            guard let self, generation == self.generation, let coordinator = parentalAccess else { return }
            if wasUnlocked || coordinator.isUnlocked {
                synchronizeParentAccess()
            } else {
                observe(coordinator)
            }
        }
    }
}

/// Feeds `ContentSafetyBoundary` the policy and the effective parental gate as
/// the scene computes them. The boundary follows the coordinator on its own;
/// the lock-state change here is a second path to the same idempotent update.
private struct ContentSafetyBoundarySync: ViewModifier {
    let boundary: ContentSafetyBoundary
    let policy: SafetyPolicy
    let parentalAccess: ParentalAccessCoordinator

    func body(content: Content) -> some View {
        content
            .onAppear(perform: update)
            .onChange(of: policy) { _, _ in update() }
            .onChange(of: parentalAccess.isUnlocked) { _, _ in update() }
            .onChange(of: ObjectIdentifier(parentalAccess)) { _, _ in update() }
    }

    private func update() {
        boundary.update(policy: policy, parentalAccess: parentalAccess)
    }
}

// MARK: - Relock on leaving the foreground

/// Account sign-ins that send the parent outside the app: Plex's web sign-in,
/// with its system sign-in prompt, the Safari fallback, or a switch to a
/// password manager, an authenticator or email. While a sign-in holds a lease,
/// leaving the foreground does not relock the parental gate at once, which
/// would tear Settings, and the sign-in inside it, down.
/// `ParentalSceneLock` bounds the wait.
///
/// Leases are held weakly: a sign-in torn down without ending its lease stops
/// counting once it is deallocated, so a lost lease never keeps the gate open.
@MainActor
final class ParentalRelockDeferral {
    final class Lease {
        fileprivate init() {}
    }

    private struct WeakLease {
        weak var lease: Lease?
    }

    static let shared = ParentalRelockDeferral()

    /// Called when the last lease ends, so a relock deferred while the app was away happens then.
    var onLastLeaseEnded: (@MainActor () -> Void)?

    private var leases: [WeakLease] = []

    init() {}

    var isActive: Bool {
        leases.removeAll { $0.lease == nil }
        return !leases.isEmpty
    }

    func begin() -> Lease {
        let lease = Lease()
        leases.append(WeakLease(lease: lease))
        return lease
    }

    func end(_ lease: Lease) {
        let wasActive = isActive
        leases.removeAll { $0.lease == nil || $0.lease === lease }
        if wasActive, leases.isEmpty {
            onLastLeaseEnded?()
        }
    }
}

/// Relocks the parental gate whenever the app leaves the foreground (any
/// scene phase other than `.active`), so protected UI never survives the
/// parent leaving.
///
/// While an account sign-in holds a `ParentalRelockDeferral` lease the relock
/// waits, so a parent can add or reconnect an account from Settings. It
/// happens as soon as the sign-in ends while the app is still away, or when
/// the app comes back after more than `gracePeriod`. Coming back sooner keeps
/// the parent where they were.
@MainActor
final class ParentalSceneLock {
    /// Long enough to find a password or a one-time code in another app; short
    /// enough that a device left on a half-finished sign-in relocks before a
    /// child picks it up.
    nonisolated static let signInGracePeriod: TimeInterval = 5 * 60

    private let deferral: ParentalRelockDeferral
    private let gracePeriod: TimeInterval
    private let now: () -> Date
    private let lock: @MainActor () -> Void
    private var phase: ScenePhase = .active
    /// When the app left the foreground with the relock deferred; `nil` otherwise.
    private var deferredSince: Date?

    init(
        deferral: ParentalRelockDeferral,
        gracePeriod: TimeInterval = ParentalSceneLock.signInGracePeriod,
        now: @escaping () -> Date = Date.init,
        lock: @escaping @MainActor () -> Void
    ) {
        self.deferral = deferral
        self.gracePeriod = gracePeriod
        self.now = now
        self.lock = lock
        followDeferral()
    }

    func scenePhaseChanged(to newPhase: ScenePhase) {
        followDeferral()
        phase = newPhase
        if newPhase == .active {
            if let deferredSince, !deferral.isActive || hasExpired(since: deferredSince) {
                relock()
            }
            deferredSince = nil
        } else if !deferral.isActive {
            relock()
        } else if let deferredSince {
            if hasExpired(since: deferredSince) {
                relock()
            }
        } else {
            deferredSince = now()
        }
    }

    private func hasExpired(since start: Date) -> Bool {
        now().timeIntervalSince(start) > gracePeriod
    }

    private func relock() {
        deferredSince = nil
        lock()
    }

    /// Re-registered on every phase change, so the instance the app keeps is the one called.
    private func followDeferral() {
        deferral.onLastLeaseEnded = { [weak self] in
            guard let self, phase != .active else { return }
            relock()
        }
    }
}
