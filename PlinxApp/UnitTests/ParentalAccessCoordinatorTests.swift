import PlinxCore
import SwiftUI
import XCTest
@testable import Plinx

@MainActor
final class ParentalAccessCoordinatorTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ParentalAccessCoordinatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_migratesLegacyPINToSecureStore() throws {
        defaults.set("2468", forKey: "plinx.parentalPin")
        let store = MemoryPINStore()

        let coordinator = ParentalAccessCoordinator(store: store, legacyDefaults: defaults)

        XCTAssertTrue(coordinator.hasPIN)
        XCTAssertNil(defaults.string(forKey: "plinx.parentalPin"))
        XCTAssertEqual(try store.readPIN(), "2468")
    }

    func test_locksOutAfterRepeatedFailuresThenRecovers() {
        let store = MemoryPINStore(pin: "2468")
        var now = Date(timeIntervalSince1970: 100)
        let coordinator = ParentalAccessCoordinator(
            store: store,
            now: { now },
            maximumAttempts: 2,
            lockoutDuration: 60,
            legacyDefaults: defaults
        )

        XCTAssertEqual(coordinator.unlock(withPIN: "0000"), .denied(remainingAttempts: 1))
        XCTAssertEqual(
            coordinator.unlock(withPIN: "1111"),
            .lockedOut(until: Date(timeIntervalSince1970: 160))
        )
        XCTAssertEqual(
            coordinator.unlock(withPIN: "2468"),
            .lockedOut(until: Date(timeIntervalSince1970: 160))
        )

        now = Date(timeIntervalSince1970: 161)
        XCTAssertEqual(coordinator.unlock(withPIN: "2468"), .allowed)
    }

    func test_changeAndRemoveRequireCurrentPIN() {
        let store = MemoryPINStore(pin: "2468")
        let coordinator = ParentalAccessCoordinator(store: store, legacyDefaults: defaults)

        XCTAssertEqual(
            coordinator.setPIN("1357", currentPIN: "0000"),
            .incorrectCurrentPIN
        )
        XCTAssertEqual(try store.readPIN(), "2468")
        XCTAssertEqual(coordinator.setPIN("1357", currentPIN: "2468"), .success)
        XCTAssertEqual(coordinator.removePIN(currentPIN: "2468"), .incorrectCurrentPIN)
        XCTAssertEqual(coordinator.removePIN(currentPIN: "1357"), .success)
        XCTAssertFalse(coordinator.hasPIN)
    }

    func test_incorrectCurrentPINDoesNotUnlockSession() {
        let coordinator = ParentalAccessCoordinator(
            store: MemoryPINStore(pin: "2468"),
            legacyDefaults: defaults
        )

        XCTAssertEqual(
            coordinator.setPIN("1357", currentPIN: "0000"),
            .incorrectCurrentPIN
        )
        XCTAssertFalse(coordinator.isUnlocked)
    }

    func test_keychainReadFailureCannotFallBackToMathChallenge() {
        let coordinator = ParentalAccessCoordinator(
            store: FailingPINStore(),
            legacyDefaults: defaults
        )

        XCTAssertFalse(coordinator.isPINStorageAvailable)
        XCTAssertTrue(coordinator.hasPIN)
        XCTAssertEqual(coordinator.unlock(withPIN: "2468"), .unavailable)
        XCTAssertEqual(coordinator.unlockWithMathChallenge(), .unavailable)
        XCTAssertFalse(coordinator.isUnlocked)
    }

    func test_lockClearsAuthorizedSession() {
        let coordinator = ParentalAccessCoordinator(
            store: MemoryPINStore(pin: "2468"),
            legacyDefaults: defaults
        )
        XCTAssertEqual(coordinator.unlock(withPIN: "2468"), .allowed)
        XCTAssertTrue(coordinator.isUnlocked)

        coordinator.lock()

        XCTAssertFalse(coordinator.isUnlocked)
    }

    func test_lockoutSurvivesCoordinatorRecreation() {
        let store = MemoryPINStore(pin: "2468")
        let now = Date(timeIntervalSince1970: 100)
        let first = ParentalAccessCoordinator(
            store: store,
            now: { now },
            maximumAttempts: 1,
            lockoutDuration: 60,
            legacyDefaults: defaults
        )
        XCTAssertEqual(
            first.unlock(withPIN: "0000"),
            .lockedOut(until: Date(timeIntervalSince1970: 160))
        )

        let recreated = ParentalAccessCoordinator(
            store: store,
            now: { now },
            maximumAttempts: 1,
            lockoutDuration: 60,
            legacyDefaults: defaults
        )

        XCTAssertEqual(
            recreated.unlock(withPIN: "2468"),
            .lockedOut(until: Date(timeIntervalSince1970: 160))
        )
    }
}

// MARK: - Safety boundary sync

/// `ContentSafetyBoundary` keeps `ContentSafetyGate.isParentUnlocked` equal to
/// the effective parental gate. Server rights, management, deletion and
/// playlist edits behind the boundary depend on it, so these tests drive the
/// coordinator directly, with no view to forward the change.
@MainActor
final class ContentSafetyBoundaryTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ContentSafetyBoundaryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_unlockOpensTheGateAndLockClosesItAtOnce() async {
        let gate = ContentSafetyGate()
        let rights = SafeAuthorizationService(base: AdministratorAuthorization(), gate: gate)
        let coordinator = makeCoordinator()
        let boundary = ContentSafetyBoundary(gate: gate)
        boundary.update(policy: .ratingOnly(), parentalAccess: coordinator)
        XCTAssertFalse(gate.isParentUnlocked)
        XCTAssertEqual(rights.authorization, .denied)

        XCTAssertEqual(coordinator.unlock(withPIN: "2468"), .allowed)
        await waitUntil { gate.isParentUnlocked }
        XCTAssertTrue(gate.isParentUnlocked)
        XCTAssertEqual(rights.authorization, .plex(isAdministrator: true, allowsMediaDeletion: true))

        coordinator.lock()
        // No main-actor turn in between: parent-only abilities end with the lock.
        XCTAssertFalse(gate.isParentUnlocked)
        XCTAssertEqual(rights.authorization, .denied)
        await settle()
        XCTAssertFalse(gate.isParentUnlocked)
        XCTAssertEqual(rights.authorization, .denied)

        // The boundary keeps following the coordinator after a full cycle.
        XCTAssertEqual(coordinator.unlock(withPIN: "2468"), .allowed)
        await waitUntil { gate.isParentUnlocked }
        XCTAssertTrue(gate.isParentUnlocked)
        coordinator.lock()
        XCTAssertFalse(gate.isParentUnlocked)
        XCTAssertEqual(rights.authorization, .denied)
    }

    func test_lockRightAfterUnlockLeavesTheGateClosed() async {
        let gate = ContentSafetyGate()
        let coordinator = makeCoordinator()
        let boundary = ContentSafetyBoundary(gate: gate)
        boundary.update(policy: .ratingOnly(), parentalAccess: coordinator)

        XCTAssertEqual(coordinator.unlock(withPIN: "2468"), .allowed)
        // A view forwards the unlock before the boundary's own copy runs.
        boundary.update(policy: .ratingOnly(), parentalAccess: coordinator)
        XCTAssertTrue(gate.isParentUnlocked)
        coordinator.lock()

        XCTAssertFalse(gate.isParentUnlocked)
        await settle()
        XCTAssertFalse(gate.isParentUnlocked)
    }

    func test_swappingToTheLockedSampleLibraryGateRelocksTheGate() async {
        let gate = ContentSafetyGate()
        let family = makeCoordinator()
        // What starting the sample library does: a fresh, locked coordinator.
        DemoPreferences.reset()
        let sample = DemoPreferences.parentalAccess
        defer { sample.lock() }
        XCTAssertFalse(sample.isUnlocked)
        let boundary = ContentSafetyBoundary(gate: gate)
        XCTAssertEqual(family.unlock(withPIN: "2468"), .allowed)
        boundary.update(policy: .ratingOnly(), parentalAccess: family)
        XCTAssertTrue(gate.isParentUnlocked)

        boundary.update(policy: .ratingOnly(), parentalAccess: sample)

        XCTAssertFalse(gate.isParentUnlocked)
        XCTAssertTrue(family.isUnlocked, "Only the effective gate decides")

        // The replaced coordinator no longer reaches the gate; the new one does.
        family.lock()
        XCTAssertEqual(family.unlock(withPIN: "2468"), .allowed)
        await settle()
        XCTAssertFalse(gate.isParentUnlocked)
        XCTAssertEqual(sample.unlock(withPIN: "2468"), .allowed)
        await waitUntil { gate.isParentUnlocked }
        XCTAssertTrue(gate.isParentUnlocked)
        sample.lock()
        XCTAssertFalse(gate.isParentUnlocked)
    }

    func test_appliesThePolicy() {
        let gate = ContentSafetyGate()
        let boundary = ContentSafetyBoundary(gate: gate)
        let policy = SafetyPolicy.ratingOnly(maxMovie: .pg, maxTV: .tvY7)

        boundary.update(policy: policy, parentalAccess: makeCoordinator())

        XCTAssertEqual(gate.policy, policy)
        XCTAssertFalse(gate.isParentUnlocked)
    }

    func test_leavingTheForegroundRelocksTheGate() async {
        let gate = ContentSafetyGate()
        let coordinator = makeCoordinator()
        let boundary = ContentSafetyBoundary(gate: gate)
        boundary.update(policy: .ratingOnly(), parentalAccess: coordinator)
        let sceneLock = ParentalSceneLock(deferral: ParentalRelockDeferral(), lock: { coordinator.lock() })

        for phase in [ScenePhase.inactive, .background] {
            XCTAssertEqual(coordinator.unlock(withPIN: "2468"), .allowed)
            await waitUntil { gate.isParentUnlocked }
            XCTAssertTrue(gate.isParentUnlocked)

            sceneLock.scenePhaseChanged(to: phase)

            XCTAssertFalse(coordinator.isUnlocked, "\(phase)")
            XCTAssertFalse(gate.isParentUnlocked, "\(phase)")
            sceneLock.scenePhaseChanged(to: .active)
        }
    }

    private func makeCoordinator() -> ParentalAccessCoordinator {
        ParentalAccessCoordinator(store: MemoryPINStore(pin: "2468"), legacyDefaults: defaults)
    }
}

// MARK: - Relock on leaving the foreground

/// `ParentalSceneLock` relocks when the app leaves the foreground, except that
/// an account sign-in in progress defers it for a bounded time.
@MainActor
final class ParentalSceneLockTests: XCTestCase {
    private var deferral: ParentalRelockDeferral!
    private var now = Date(timeIntervalSince1970: 1_000)
    private var locks = 0
    private var sceneLock: ParentalSceneLock!

    override func setUp() {
        super.setUp()
        deferral = ParentalRelockDeferral()
        now = Date(timeIntervalSince1970: 1_000)
        locks = 0
        sceneLock = ParentalSceneLock(
            deferral: deferral,
            gracePeriod: 300,
            now: { [unowned self] in self.now },
            lock: { [unowned self] in self.locks += 1 }
        )
    }

    override func tearDown() {
        sceneLock = nil
        deferral = nil
        super.tearDown()
    }

    func test_withoutSignIn_anyPhaseOtherThanActiveRelocks() {
        sceneLock.scenePhaseChanged(to: .inactive)
        XCTAssertEqual(locks, 1)
        sceneLock.scenePhaseChanged(to: .background)
        XCTAssertEqual(locks, 2)
        sceneLock.scenePhaseChanged(to: .active)
        XCTAssertEqual(locks, 2)
    }

    func test_signIn_keepsTheGateThroughThePromptAndAnAppSwitch() {
        let lease = deferral.begin()

        // The system sign-in prompt, then a switch to a password manager.
        sceneLock.scenePhaseChanged(to: .inactive)
        sceneLock.scenePhaseChanged(to: .active)
        sceneLock.scenePhaseChanged(to: .inactive)
        sceneLock.scenePhaseChanged(to: .background)
        now += 240
        sceneLock.scenePhaseChanged(to: .inactive)
        sceneLock.scenePhaseChanged(to: .active)
        XCTAssertEqual(locks, 0)

        deferral.end(lease)
        XCTAssertEqual(locks, 0, "Finishing in the foreground keeps the parent where they are")

        sceneLock.scenePhaseChanged(to: .background)
        XCTAssertEqual(locks, 1, "Once the sign-in ends, leaving relocks at once")
    }

    func test_signInEndingWhileAway_relocksAtOnce() {
        let lease = deferral.begin()
        sceneLock.scenePhaseChanged(to: .inactive)
        sceneLock.scenePhaseChanged(to: .background)
        XCTAssertEqual(locks, 0)

        deferral.end(lease)

        XCTAssertEqual(locks, 1)
    }

    func test_signInCancelledAtTheSystemPrompt_failsClosed() {
        // The prompt leaves the scene inactive; ending the sign-in there is still away.
        let lease = deferral.begin()
        sceneLock.scenePhaseChanged(to: .inactive)

        deferral.end(lease)

        XCTAssertEqual(locks, 1)
        sceneLock.scenePhaseChanged(to: .active)
        XCTAssertEqual(locks, 1)
    }

    func test_comingBackAfterTheGracePeriod_relocksBeforeTheAppIsActive() {
        let lease = deferral.begin()
        sceneLock.scenePhaseChanged(to: .inactive)
        sceneLock.scenePhaseChanged(to: .background)
        now += 301

        sceneLock.scenePhaseChanged(to: .inactive)
        XCTAssertEqual(locks, 1)
        sceneLock.scenePhaseChanged(to: .active)
        XCTAssertEqual(locks, 1)

        deferral.end(lease)
        XCTAssertEqual(locks, 1, "Ending in the foreground does not lock again")
    }

    func test_comingBackAfterTheGracePeriod_relocksEvenWithoutAnInactivePhase() {
        let lease = deferral.begin()
        sceneLock.scenePhaseChanged(to: .background)
        now += 301

        sceneLock.scenePhaseChanged(to: .active)

        XCTAssertEqual(locks, 1)
        withExtendedLifetime(lease) {}
    }

    func test_eachDepartureGetsItsOwnGracePeriod() {
        let lease = deferral.begin()
        sceneLock.scenePhaseChanged(to: .background)
        now += 200
        sceneLock.scenePhaseChanged(to: .active)
        sceneLock.scenePhaseChanged(to: .background)
        now += 200
        sceneLock.scenePhaseChanged(to: .active)

        XCTAssertEqual(locks, 0)
        withExtendedLifetime(lease) {}
    }

    func test_aLeaseReleasedWithoutEnding_stopsDeferring() {
        var lease: ParentalRelockDeferral.Lease? = deferral.begin()
        withExtendedLifetime(lease) {
            sceneLock.scenePhaseChanged(to: .background)
            XCTAssertEqual(locks, 0)
        }

        lease = nil
        XCTAssertNil(lease)
        XCTAssertFalse(deferral.isActive)
        sceneLock.scenePhaseChanged(to: .inactive)

        XCTAssertEqual(locks, 1)
    }
}

/// Plex rights of a server administrator, before the boundary applies the parental gate.
private final class AdministratorAuthorization: MediaAuthorizationService {
    var authorization: MediaAuthorization {
        .plex(isAdministrator: true, allowsMediaDeletion: true)
    }
}

@MainActor
private func settle() async {
    for _ in 0..<5 {
        await Task.yield()
    }
    try? await Task.sleep(for: .milliseconds(20))
}

@MainActor
private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(2)) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition(), clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private final class MemoryPINStore: ParentalPINStoring {
    private var pin: String?

    init(pin: String? = nil) {
        self.pin = pin
    }

    func readPIN() throws -> String? {
        pin
    }

    func writePIN(_ pin: String) throws {
        self.pin = pin
    }

    func deletePIN() throws {
        pin = nil
    }
}

private struct FailingPINStore: ParentalPINStoring {
    private enum StoreError: Error {
        case unavailable
    }

    func readPIN() throws -> String? {
        throw StoreError.unavailable
    }

    func writePIN(_ pin: String) throws {
        throw StoreError.unavailable
    }

    func deletePIN() throws {
        throw StoreError.unavailable
    }
}

// MARK: - Profile picker approval rules

/// The parental rules of the profile picker (`PlinxProfileSwitchRules`) and of
/// approvals requested from it (`PlinxParentalRequest`).
@MainActor
final class PlinxProfilePickerApprovalTests: XCTestCase {
    func test_continuingAsLastActiveProfile_needsNoGate() {
        XCTAssertFalse(
            PlinxProfileSwitchRules.requiresParentalApproval(
                choosingProfileID: "kid",
                mode: .activateProfile,
                lastActiveProfileID: "kid"
            )
        )
    }

    func test_switchingToAnotherProfile_needsTheGate() {
        XCTAssertTrue(
            PlinxProfileSwitchRules.requiresParentalApproval(
                choosingProfileID: "parent",
                mode: .activateProfile,
                lastActiveProfileID: "kid"
            )
        )
    }

    func test_withNoLastActiveProfile_everyChoiceNeedsTheGate() {
        // A removed Plex Home user, a deleted profile or a removed account
        // clears the remembered profile without a parent present.
        for profileID in ["kid", "parent", "plexhome.owner"] {
            XCTAssertTrue(
                PlinxProfileSwitchRules.requiresParentalApproval(
                    choosingProfileID: profileID,
                    mode: .activateProfile,
                    lastActiveProfileID: nil
                ),
                "\(profileID) must not open without the parental gate"
            )
        }
    }

    func test_choosingHomeUserDuringAccountSetup_isNotGatedAgain() {
        let mode = ProfileSwitcherViewModel.Mode.chooseHomeUser(accountID: "account", onChoose: { _, _ in })

        XCTAssertFalse(
            PlinxProfileSwitchRules.requiresParentalApproval(
                choosingProfileID: "home-user",
                mode: mode,
                lastActiveProfileID: nil
            )
        )
        XCTAssertFalse(
            PlinxProfileSwitchRules.requiresParentalApproval(
                choosingProfileID: "home-user",
                mode: mode,
                lastActiveProfileID: "kid"
            )
        )
    }

    func test_approvalThatKeepsTheGateUnlocked_isDroppedWhenTheGateRelockedFirst() {
        // Opening profile management keeps the gate unlocked. If the app left
        // the foreground before the gate screen closed, the sheet must not open.
        let request = PlinxParentalRequest(relocksAfterAction: false, action: {})

        XCTAssertFalse(request.runsAfterApproval(isParentalGateUnlocked: false))
        XCTAssertTrue(request.runsAfterApproval(isParentalGateUnlocked: true))
    }

    func test_oneShotApproval_runsTheApprovedAction() {
        let request = PlinxParentalRequest(relocksAfterAction: true, action: {})

        XCTAssertTrue(request.runsAfterApproval(isParentalGateUnlocked: true))
        XCTAssertTrue(request.runsAfterApproval(isParentalGateUnlocked: false))
    }
}
