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
