import Foundation
import Observation
import PlinxCore

// ─────────────────────────────────────────────────────────────────────────────
// PlinxCloudSettingsSync
//
// Optional, parent-enabled sync of family preferences through the iCloud
// key-value store (`NSUbiquitousKeyValueStore`). Values live in the family's
// own iCloud account; Plinx operates no server and never receives them, so the
// zero-collection baseline is unchanged.
//
// Safety rules:
// - Sync is off by default and enabled per device behind the parental gate,
//   because several children can share one Apple ID with different limits.
// - The parent PIN, Youtarr connection and credentials, download preferences,
//   download ownership, and device-specific layout tuning never sync.
// - Incoming values are validated against the same allow-lists the UI offers;
//   anything unrecognized is ignored and the local value stays in force.
// - An iCloud account change on the device turns sync off until a parent
//   re-enables it, so a different account's settings never apply silently.
// ─────────────────────────────────────────────────────────────────────────────

/// The subset of `NSUbiquitousKeyValueStore` used by Plinx, so tests can use
/// an in-memory store.
protocol PlinxCloudKeyValueStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: PlinxCloudKeyValueStore {}

/// Supplies the current iCloud account identity so an account change made
/// while Plinx was not running is detected before any value is applied.
protocol PlinxCloudIdentityProviding {
    /// An archived form of the current iCloud identity, or `nil` when iCloud is
    /// unavailable or the identity cannot be read.
    func currentIdentity() -> Data?
}

struct PlinxUbiquityIdentityProvider: PlinxCloudIdentityProviding {
    func currentIdentity() -> Data? {
        guard let token = FileManager.default.ubiquityIdentityToken else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
    }
}

/// A property-list value that can round-trip through the iCloud key-value store.
enum PlinxSyncValue: Equatable {
    case bool(Bool)
    case int(Int)
    case string(String)
    case stringArray([String])
    case data(Data)

    init?(propertyList value: Any?) {
        guard let value else { return nil }
        if let number = value as? NSNumber {
            // Booleans bridge to the CFBoolean singletons; every other number
            // is stored as an integer.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .int(number.intValue)
            }
        } else if let string = value as? String {
            self = .string(string)
        } else if let strings = value as? [String] {
            self = .stringArray(strings)
        } else if let data = value as? Data {
            self = .data(data)
        } else {
            return nil
        }
    }

    var propertyList: Any {
        switch self {
        case .bool(let value): value
        case .int(let value): value
        case .string(let value): value
        case .stringArray(let value): value
        case .data(let value): value
        }
    }
}

/// One synced preference: how to read it locally and how to apply a
/// validated remote value.
struct PlinxSyncedSetting {
    /// Stable name used to build the iCloud key. Never rename an entry.
    let name: String
    /// The current local value, or `nil` when the device has never set it
    /// (an unset value is never uploaded, so it cannot overwrite the cloud).
    let read: @MainActor () -> PlinxSyncValue?
    /// Applies a remote value. Returns `false` when the value is rejected.
    let apply: @MainActor (PlinxSyncValue) -> Bool
}

@MainActor
@Observable
final class PlinxCloudSettingsSync {
    enum DisableReason: Equatable {
        case accountChanged
    }

    static let enabledKey = "plinx.iCloudSync.enabled"
    /// Set when sync was turned on before iCloud had delivered this account's
    /// existing settings; uploads wait until they arrive.
    static let awaitingInitialSyncKey = "plinx.iCloudSync.awaitingInitialSync"
    /// Archived iCloud identity recorded when sync was turned on.
    static let identityKey = "plinx.iCloudSync.identity"
    static let cloudKeyPrefix = "plinx.sync.v1."

    private(set) var isEnabled: Bool
    /// Why sync last turned itself off, shown to the parent in settings.
    private(set) var disableReason: DisableReason?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cloud: PlinxCloudKeyValueStore
    @ObservationIgnored private let settings: [PlinxSyncedSetting]
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var isPushScheduled = false
    @ObservationIgnored private let identityProvider: PlinxCloudIdentityProviding
    @ObservationIgnored private let initialSyncGracePeriod: TimeInterval
    @ObservationIgnored private var initialSyncFallback: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        cloud: PlinxCloudKeyValueStore = NSUbiquitousKeyValueStore.default,
        settings: [PlinxSyncedSetting],
        notificationCenter: NotificationCenter = .default,
        identityProvider: PlinxCloudIdentityProviding = PlinxUbiquityIdentityProvider(),
        initialSyncGracePeriod: TimeInterval = 60
    ) {
        self.defaults = defaults
        self.cloud = cloud
        self.settings = settings
        self.notificationCenter = notificationCenter
        self.identityProvider = identityProvider
        // How long to wait for iCloud's first download before treating an
        // empty store as genuinely empty during the same session.
        self.initialSyncGracePeriod = initialSyncGracePeriod
        isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    /// True while uploads wait for iCloud to deliver existing settings.
    var isAwaitingInitialSync: Bool {
        defaults.bool(forKey: Self.awaitingInitialSyncKey)
    }

    static func cloudKey(for name: String) -> String {
        cloudKeyPrefix + name
    }

    /// Resumes syncing at launch when a parent previously enabled it.
    func start() {
        guard isEnabled else { return }

        // Fail closed before touching any value: an iCloud account that
        // changed while Plinx was not running must not apply its settings.
        if identityChangedSinceEnabled() {
            disableAfterAccountChange()
            return
        }

        beginObserving()
        cloud.synchronize()
        applyCloudValues(names: nil)

        if isAwaitingInitialSync {
            // A whole session has passed since sync was turned on. If iCloud
            // still holds nothing, this device's settings become the seed.
            finishInitialSync()
        } else {
            pushLocalChanges()
        }
    }

    /// Turns sync on or off for this device. Turning it on adopts settings
    /// already in iCloud and uploads any this device has that iCloud lacks;
    /// turning it off keeps this device's current settings.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)

        if enabled {
            disableReason = nil
            recordCurrentIdentity()
            cloud.synchronize()
            beginObserving()

            if cloudHasSyncedSettings {
                applyCloudValues(names: nil)
                pushLocalChanges()
            } else {
                // iCloud's first download can arrive after `synchronize()`
                // returns. Uploading now could replace the family's settings
                // with this device's defaults, so wait for that download (or a
                // grace period with nothing arriving) before seeding iCloud.
                defaults.set(true, forKey: Self.awaitingInitialSyncKey)
                scheduleInitialSyncFallback()
            }
        } else {
            initialSyncFallback?.cancel()
            initialSyncFallback = nil
            defaults.removeObject(forKey: Self.awaitingInitialSyncKey)
            defaults.removeObject(forKey: Self.identityKey)
            stopObserving()
        }
    }

    /// Ends the wait for iCloud's first download: adopts whatever arrived,
    /// then uploads settings iCloud still lacks.
    func finishInitialSync() {
        guard isEnabled, isAwaitingInitialSync else { return }
        initialSyncFallback?.cancel()
        initialSyncFallback = nil
        defaults.removeObject(forKey: Self.awaitingInitialSyncKey)
        applyCloudValues(names: nil)
        pushLocalChanges()
    }

    private var cloudHasSyncedSettings: Bool {
        settings.contains { cloud.object(forKey: Self.cloudKey(for: $0.name)) != nil }
    }

    private func scheduleInitialSyncFallback() {
        initialSyncFallback?.cancel()
        let delay = initialSyncGracePeriod
        initialSyncFallback = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(delay, 0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.finishInitialSync()
        }
    }

    // MARK: - Account identity

    private func recordCurrentIdentity() {
        if let identity = identityProvider.currentIdentity() {
            defaults.set(identity, forKey: Self.identityKey)
        } else {
            defaults.removeObject(forKey: Self.identityKey)
        }
    }

    /// True only when both the recorded and current identities are known and
    /// differ. An unavailable identity (signed out, iCloud restricted) stops
    /// key-value traffic by itself, so it is not treated as a new account.
    private func identityChangedSinceEnabled() -> Bool {
        guard let current = identityProvider.currentIdentity() else { return false }
        guard let recorded = defaults.data(forKey: Self.identityKey) else {
            // Sync was enabled while no identity was readable; adopt this one.
            defaults.set(current, forKey: Self.identityKey)
            return false
        }
        return !Self.identitiesMatch(recorded, current)
    }

    private static func identitiesMatch(_ lhs: Data, _ rhs: Data) -> Bool {
        if lhs == rhs { return true }
        guard let left = unarchive(lhs), let right = unarchive(rhs) else { return false }
        return left.isEqual(right)
    }

    private static func unarchive(_ data: Data) -> NSObject? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = false
        defer { unarchiver.finishDecoding() }
        return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSObject
    }

    private func disableAfterAccountChange() {
        setEnabled(false)
        disableReason = .accountChanged
    }

    // MARK: - Sync

    /// Applies cloud values that differ from local ones. `names == nil`
    /// considers every synced setting.
    func applyCloudValues(names: Set<String>?) {
        guard isEnabled else { return }
        for setting in settings where names?.contains(setting.name) ?? true {
            guard
                let remote = PlinxSyncValue(propertyList: cloud.object(forKey: Self.cloudKey(for: setting.name))),
                remote != setting.read()
            else { continue }
            _ = setting.apply(remote)
        }
    }

    /// Uploads local values that differ from the cloud copy. Values the device
    /// has never set are skipped, and nothing is ever deleted from iCloud.
    /// Nothing is uploaded while waiting for iCloud's first download.
    func pushLocalChanges() {
        guard isEnabled, !isAwaitingInitialSync else { return }
        for setting in settings {
            guard let local = setting.read() else { continue }
            let key = Self.cloudKey(for: setting.name)
            if PlinxSyncValue(propertyList: cloud.object(forKey: key)) != local {
                cloud.set(local.propertyList, forKey: key)
            }
        }
    }

    /// Handles a `NSUbiquitousKeyValueStore.didChangeExternallyNotification`.
    func handleExternalChange(reason: Int?, changedKeys: [String]?) {
        guard isEnabled else { return }
        switch reason ?? NSUbiquitousKeyValueStoreServerChange {
        case NSUbiquitousKeyValueStoreAccountChange:
            // Fail closed: a different iCloud account must not silently replace
            // this device's parental settings.
            disableAfterAccountChange()
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            // Plinx stores a few kilobytes; nothing to recover.
            break
        default:
            let names = changedKeys.map { keys in
                Set(keys.compactMap { key -> String? in
                    guard key.hasPrefix(Self.cloudKeyPrefix) else { return nil }
                    return String(key.dropFirst(Self.cloudKeyPrefix.count))
                })
            }
            if isAwaitingInitialSync {
                // The first download arrived: adopt everything iCloud holds,
                // then upload what it lacks.
                finishInitialSync()
            } else {
                applyCloudValues(names: names)
            }
        }
    }

    // MARK: - Observation

    private func beginObserving() {
        guard observers.isEmpty else { return }

        observers.append(
            notificationCenter.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: cloud,
                queue: .main
            ) { [weak self] notification in
                let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
                let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
                Task { @MainActor in
                    self?.handleExternalChange(reason: reason, changedKeys: keys)
                }
            }
        )

        observers.append(
            notificationCenter.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: defaults,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleLocalPush()
                }
            }
        )
    }

    private func stopObserving() {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    /// Coalesces bursts of local writes (for example dragging the volume
    /// slider) into one comparison pass. Remote values applied by this object
    /// compare equal afterwards, so applying them never echoes back.
    private func scheduleLocalPush() {
        guard isEnabled, !isPushScheduled else { return }
        isPushScheduled = true
        Task { @MainActor in
            await Task.yield()
            isPushScheduled = false
            pushLocalChanges()
        }
    }
}
