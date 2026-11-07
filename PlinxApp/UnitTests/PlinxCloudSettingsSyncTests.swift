import XCTest
import PlinxCore
@testable import Plinx

private final class InMemoryCloudStore: PlinxCloudKeyValueStore {
    var values: [String: Any] = [:]
    private(set) var synchronizeCount = 0
    private(set) var writeCount = 0

    func object(forKey key: String) -> Any? { values[key] }

    func set(_ value: Any?, forKey key: String) {
        writeCount += 1
        values[key] = value
    }

    func synchronize() -> Bool {
        synchronizeCount += 1
        return true
    }
}

private final class FakeIdentityProvider: PlinxCloudIdentityProviding {
    var identity: String?

    init(_ identity: String?) {
        self.identity = identity
    }

    func currentIdentity() -> Data? {
        identity.map { Data($0.utf8) }
    }
}

@MainActor
final class PlinxCloudSettingsSyncTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var cloud: InMemoryCloudStore!
    private var settingsManager: SettingsManager!
    private var identity: FakeIdentityProvider!

    override func setUp() {
        super.setUp()
        suiteName = "PlinxCloudSettingsSyncTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        cloud = InMemoryCloudStore()
        settingsManager = SettingsManager(userDefaults: defaults)
        identity = FakeIdentityProvider("account-a")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        cloud = nil
        settingsManager = nil
        identity = nil
        super.tearDown()
    }

    private func makeSync() -> PlinxCloudSettingsSync {
        PlinxCloudSettingsSync(
            defaults: defaults,
            cloud: cloud,
            settings: PlinxSyncedSettingsCatalog.standard(defaults: defaults, settingsManager: settingsManager),
            notificationCenter: NotificationCenter(),
            identityProvider: identity,
            // Long enough that the in-session fallback never fires during a test.
            initialSyncGracePeriod: 3_600
        )
    }

    /// Puts a value in iCloud so enabling does not wait for a first download.
    private func seedCloud() {
        cloud.values[cloudKey("plinx.homeCombineMoviesTV")] = true
    }

    private func cloudKey(_ name: String) -> String {
        PlinxCloudSettingsSync.cloudKey(for: name)
    }

    // MARK: - Opt-in

    func test_syncIsOffByDefaultAndStartDoesNotTouchICloud() {
        defaults.set("PG", forKey: "plinx.maxMovieRating")
        let sync = makeSync()

        sync.start()

        XCTAssertFalse(sync.isEnabled)
        XCTAssertEqual(cloud.synchronizeCount, 0)
        XCTAssertTrue(cloud.values.isEmpty)
    }

    func test_enabledStateIsRememberedPerDevice() {
        makeSync().setEnabled(true)

        XCTAssertTrue(defaults.bool(forKey: PlinxCloudSettingsSync.enabledKey))
        XCTAssertTrue(makeSync().isEnabled)
    }

    // MARK: - Enabling

    func test_enablingWithEmptyCloudWaitsThenUploadsSetValuesOnly() {
        defaults.set("PG", forKey: "plinx.maxMovieRating")
        defaults.set(false, forKey: "plinx.excludeUnrated")
        settingsManager.setMaxVolumePercent(55)
        let sync = makeSync()

        sync.setEnabled(true)
        XCTAssertTrue(sync.isAwaitingInitialSync)
        XCTAssertTrue(cloud.values.isEmpty, "Nothing uploads before iCloud's first download")

        sync.finishInitialSync()

        XCTAssertFalse(sync.isAwaitingInitialSync)
        XCTAssertEqual(cloud.values[cloudKey("plinx.maxMovieRating")] as? String, "PG")
        XCTAssertEqual(cloud.values[cloudKey("plinx.excludeUnrated")] as? Bool, false)
        XCTAssertEqual(cloud.values[cloudKey("strimr.playback.maxVolumePercent")] as? Int, 55)
        XCTAssertNil(
            cloud.values[cloudKey("plinx.maxTVRating")],
            "A value this device never set must not be uploaded"
        )
    }

    func test_enablingAdoptsExistingCloudSettings() {
        defaults.set("G", forKey: "plinx.maxMovieRating")
        defaults.set("blue", forKey: "plinx.accentColorName")
        cloud.values[cloudKey("plinx.maxMovieRating")] = "PG"
        cloud.values[cloudKey("strimr.playback.maxVolumePercent")] = 40
        cloud.values[cloudKey("strimr.interface.hiddenLibraryIds")] = ["7", "3"]

        makeSync().setEnabled(true)

        XCTAssertEqual(defaults.string(forKey: "plinx.maxMovieRating"), "PG")
        XCTAssertEqual(settingsManager.playback.maxVolumePercent, 40)
        XCTAssertEqual(settingsManager.interface.hiddenLibraryIds, ["3", "7"])
        XCTAssertEqual(
            cloud.values[cloudKey("plinx.accentColorName")] as? String,
            "blue",
            "Settings iCloud lacks are uploaded from this device"
        )
    }

    func test_newDeviceAdoptsSettingsThatArriveAfterEnabling() {
        // This device has its own (default) volume and a local rating.
        settingsManager.setMaxVolumePercent(70)
        defaults.set("PG", forKey: "plinx.maxMovieRating")
        let sync = makeSync()
        sync.setEnabled(true)

        // iCloud's first download delivers the family's volume cap.
        cloud.values[cloudKey("strimr.playback.maxVolumePercent")] = 40
        sync.handleExternalChange(
            reason: NSUbiquitousKeyValueStoreInitialSyncChange,
            changedKeys: [cloudKey("strimr.playback.maxVolumePercent")]
        )

        XCTAssertEqual(settingsManager.playback.maxVolumePercent, 40)
        XCTAssertEqual(
            cloud.values[cloudKey("strimr.playback.maxVolumePercent")] as? Int,
            40,
            "The family's value must not be replaced by this device's default"
        )
        XCTAssertEqual(cloud.values[cloudKey("plinx.maxMovieRating")] as? String, "PG")
        XCTAssertFalse(sync.isAwaitingInitialSync)
    }

    func test_untouchedStrimrDefaultsAreNotUploaded() {
        let sync = makeSync()
        sync.setEnabled(true)
        sync.finishInitialSync()

        XCTAssertNil(cloud.values[cloudKey("strimr.playback.maxVolumePercent")])
        XCTAssertNil(cloud.values[cloudKey("strimr.interface.hiddenLibraryIds")])
        XCTAssertNil(cloud.values[cloudKey("strimr.interface.displayCollections")])
    }

    func test_launchAfterAWaitedSessionSeedsAnEmptyCloud() {
        defaults.set("PG", forKey: "plinx.maxMovieRating")
        makeSync().setEnabled(true)
        XCTAssertTrue(cloud.values.isEmpty)

        let relaunched = makeSync()
        relaunched.start()

        XCTAssertFalse(relaunched.isAwaitingInitialSync)
        XCTAssertEqual(cloud.values[cloudKey("plinx.maxMovieRating")] as? String, "PG")
    }

    // MARK: - Validation

    func test_invalidRemoteValuesAreIgnored() {
        defaults.set("G", forKey: "plinx.maxMovieRating")
        defaults.set("TV-Y", forKey: "plinx.maxTVRating")
        defaults.set("green", forKey: "plinx.accentColorName")
        settingsManager.setMaxVolumePercent(60)
        cloud.values[cloudKey("plinx.maxMovieRating")] = "TV-MA"  // not a movie rating
        cloud.values[cloudKey("plinx.maxTVRating")] = "NC-99"
        cloud.values[cloudKey("plinx.accentColorName")] = "chartreuse"
        cloud.values[cloudKey("strimr.playback.maxVolumePercent")] = 150
        cloud.values[cloudKey("plinx.excludeUnrated")] = "no"
        cloud.values[cloudKey("plinx.homeHiddenLibraryIds")] = "not json"

        makeSync().setEnabled(true)

        XCTAssertEqual(defaults.string(forKey: "plinx.maxMovieRating"), "G")
        XCTAssertEqual(defaults.string(forKey: "plinx.maxTVRating"), "TV-Y")
        XCTAssertEqual(defaults.string(forKey: "plinx.accentColorName"), "green")
        XCTAssertEqual(settingsManager.playback.maxVolumePercent, 60)
        XCTAssertNil(defaults.object(forKey: "plinx.excludeUnrated"))
        XCTAssertNil(defaults.object(forKey: "plinx.homeHiddenLibraryIds"))
    }

    func test_oversizedIdentifierListsAreIgnored() {
        let ids = (0...PlinxSyncedSettingsCatalog.maximumIdentifierCount).map(String.init)
        cloud.values[cloudKey("strimr.interface.hiddenLibraryIds")] = ids

        makeSync().setEnabled(true)

        XCTAssertEqual(settingsManager.interface.hiddenLibraryIds, [])
    }

    func test_boolAndIntegerValuesStayDistinct() {
        XCTAssertEqual(PlinxSyncValue(propertyList: true), .bool(true))
        XCTAssertEqual(PlinxSyncValue(propertyList: NSNumber(value: true)), .bool(true))
        XCTAssertEqual(PlinxSyncValue(propertyList: 1), .int(1))
        XCTAssertEqual(PlinxSyncValue(propertyList: NSNumber(value: 0)), .int(0))
        XCTAssertNil(PlinxSyncValue(propertyList: nil))
        XCTAssertNil(PlinxSyncValue(propertyList: Date()))
    }

    // MARK: - Ongoing sync

    func test_externalChangeAppliesOnlyChangedPlinxKeys() {
        seedCloud()
        let sync = makeSync()
        sync.setEnabled(true)
        cloud.values[cloudKey("plinx.maxTVRating")] = "TV-Y7"
        cloud.values[cloudKey("plinx.accentColorName")] = "pink"

        sync.handleExternalChange(
            reason: NSUbiquitousKeyValueStoreServerChange,
            changedKeys: [cloudKey("plinx.maxTVRating"), "unrelated.key"]
        )

        XCTAssertEqual(defaults.string(forKey: "plinx.maxTVRating"), "TV-Y7")
        XCTAssertNil(defaults.string(forKey: "plinx.accentColorName"), "Unlisted keys are not applied")
    }

    func test_localChangesArePushedWithoutEchoWrites() {
        seedCloud()
        let sync = makeSync()
        sync.setEnabled(true)
        let writesAfterEnable = cloud.writeCount

        sync.pushLocalChanges()
        XCTAssertEqual(cloud.writeCount, writesAfterEnable, "Unchanged values are not rewritten")

        defaults.set(true, forKey: "plinx.babyLockEnabled")
        sync.pushLocalChanges()
        XCTAssertEqual(cloud.values[cloudKey("plinx.babyLockEnabled")] as? Bool, true)
    }

    func test_accountChangeTurnsSyncOffAndStopsApplyingRemoteValues() {
        defaults.set("G", forKey: "plinx.maxMovieRating")
        let sync = makeSync()
        sync.setEnabled(true)

        sync.handleExternalChange(reason: NSUbiquitousKeyValueStoreAccountChange, changedKeys: nil)
        cloud.values[cloudKey("plinx.maxMovieRating")] = "PG-13"
        sync.handleExternalChange(
            reason: NSUbiquitousKeyValueStoreServerChange,
            changedKeys: [cloudKey("plinx.maxMovieRating")]
        )

        XCTAssertFalse(sync.isEnabled)
        XCTAssertEqual(sync.disableReason, .accountChanged)
        XCTAssertFalse(defaults.bool(forKey: PlinxCloudSettingsSync.enabledKey))
        XCTAssertEqual(defaults.string(forKey: "plinx.maxMovieRating"), "G")
    }

    func test_disablingKeepsLocalSettingsAndStopsPushing() {
        defaults.set("PG", forKey: "plinx.maxMovieRating")
        let sync = makeSync()
        sync.setEnabled(true)
        sync.finishInitialSync()
        sync.setEnabled(false)

        defaults.set("G", forKey: "plinx.maxMovieRating")
        sync.pushLocalChanges()

        XCTAssertEqual(defaults.string(forKey: "plinx.maxMovieRating"), "G")
        XCTAssertEqual(cloud.values[cloudKey("plinx.maxMovieRating")] as? String, "PG")
    }

    func test_accountChangedWhileClosedTurnsSyncOffBeforeApplyingValues() {
        defaults.set("G", forKey: "plinx.maxMovieRating")
        seedCloud()
        makeSync().setEnabled(true)

        // While Plinx was closed the device signed in to another iCloud
        // account whose store allows PG-13.
        identity.identity = "account-b"
        cloud.values[cloudKey("plinx.maxMovieRating")] = "PG-13"
        let relaunched = makeSync()
        relaunched.start()

        XCTAssertFalse(relaunched.isEnabled)
        XCTAssertEqual(relaunched.disableReason, .accountChanged)
        XCTAssertEqual(defaults.string(forKey: "plinx.maxMovieRating"), "G")
    }

    func test_sameAccountAtLaunchKeepsSyncing() {
        seedCloud()
        makeSync().setEnabled(true)
        cloud.values[cloudKey("plinx.maxMovieRating")] = "PG"

        let relaunched = makeSync()
        relaunched.start()

        XCTAssertTrue(relaunched.isEnabled)
        XCTAssertEqual(defaults.string(forKey: "plinx.maxMovieRating"), "PG")
    }

    func test_unavailableIdentityAtLaunchIsNotTreatedAsAccountChange() {
        seedCloud()
        makeSync().setEnabled(true)

        identity.identity = nil
        let relaunched = makeSync()
        relaunched.start()

        XCTAssertTrue(relaunched.isEnabled)
        XCTAssertNil(relaunched.disableReason)
    }

    // MARK: - Scope

    func test_secretAndDeviceScopedSettingsNeverSync() {
        let names = PlinxSyncedSettingsCatalog
            .standard(defaults: defaults, settingsManager: settingsManager)
            .map(\.name)

        XCTAssertEqual(Set(names).count, names.count, "Sync names must be unique")
        for name in names {
            let lowered = name.lowercased()
            XCTAssertFalse(lowered.contains("pin"), name)
            XCTAssertFalse(lowered.contains("youtarr"), name)
            XCTAssertFalse(lowered.contains("download"), name)
            XCTAssertFalse(lowered.contains("icloudsync"), name)
            XCTAssertFalse(lowered.contains("banner"), name)
        }
    }
}
