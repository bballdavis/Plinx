import Foundation
import Observation

protocol ParentalPINStoring {
    func readPIN() throws -> String?
    func writePIN(_ pin: String) throws
    func deletePIN() throws
}

struct KeychainParentalPINStore: ParentalPINStoring {
    private let keychain: Keychain
    private let key = "plinx.parental.pin"

    init(service: String = Bundle.main.bundleIdentifier ?? "com.plinx.app") {
        keychain = Keychain(service: service)
    }

    func readPIN() throws -> String? {
        try keychain.string(forKey: key)
    }

    func writePIN(_ pin: String) throws {
        try keychain.setString(pin, forKey: key)
    }

    func deletePIN() throws {
        try keychain.deleteValue(forKey: key)
    }
}

@MainActor
@Observable
final class ParentalAccessCoordinator {
    enum UnlockResult: Equatable {
        case allowed
        case denied(remainingAttempts: Int)
        case lockedOut(until: Date)
        case unavailable
    }

    enum PINMutationResult: Equatable {
        case success
        case invalidFormat
        case incorrectCurrentPIN
        case lockedOut(until: Date)
        case storageFailure
    }

    private(set) var isUnlocked = false
    private(set) var hasPIN = false
    private(set) var isPINStorageAvailable = true
    private(set) var failedAttempts = 0
    private(set) var lockoutUntil: Date?

    private let store: any ParentalPINStoring
    private let now: () -> Date
    private let maximumAttempts: Int
    private let lockoutDuration: TimeInterval
    private let legacyDefaults: UserDefaults
    private let legacyPINKey = "plinx.parentalPin"
    private let failedAttemptsKey = "plinx.parental.failedAttempts"
    private let lockoutUntilKey = "plinx.parental.lockoutUntil"

    init(
        store: any ParentalPINStoring = KeychainParentalPINStore(),
        now: @escaping () -> Date = Date.init,
        maximumAttempts: Int = 5,
        lockoutDuration: TimeInterval = 60,
        legacyDefaults: UserDefaults = .standard
    ) {
        self.store = store
        self.now = now
        self.maximumAttempts = max(1, maximumAttempts)
        self.lockoutDuration = max(1, lockoutDuration)
        self.legacyDefaults = legacyDefaults
        migrateLegacyPINIfNeeded()
        restoreRateLimitState()
        refreshPINStatus()
    }

    func unlock(withPIN candidate: String) -> UnlockResult {
        if let activeLockout = activeLockoutDate() {
            return .lockedOut(until: activeLockout)
        }

        let storedPIN: String?
        do {
            storedPIN = try store.readPIN()
            isPINStorageAvailable = true
        } catch {
            isPINStorageAvailable = false
            hasPIN = true
            return .unavailable
        }

        guard let storedPIN, !storedPIN.isEmpty else {
            hasPIN = false
            return .unavailable
        }
        hasPIN = true

        guard candidate == storedPIN else {
            failedAttempts += 1
            if failedAttempts >= maximumAttempts {
                let until = now().addingTimeInterval(lockoutDuration)
                lockoutUntil = until
                persistRateLimitState()
                return .lockedOut(until: until)
            }
            persistRateLimitState()
            return .denied(remainingAttempts: maximumAttempts - failedAttempts)
        }

        resetRateLimitState()
        isUnlocked = true
        return .allowed
    }

    func unlockWithMathChallenge() -> UnlockResult {
        refreshPINStatus()
        guard isPINStorageAvailable, !hasPIN else { return .unavailable }
        isUnlocked = true
        resetRateLimitState()
        return .allowed
    }

    func setPIN(_ newPIN: String, currentPIN: String?) -> PINMutationResult {
        guard Self.isValidPIN(newPIN) else { return .invalidFormat }

        if hasPIN {
            guard let currentPIN else { return .incorrectCurrentPIN }
            switch verifyCurrentPIN(currentPIN) {
            case .success:
                break
            case .incorrectCurrentPIN:
                return .incorrectCurrentPIN
            case let .lockedOut(until):
                return .lockedOut(until: until)
            default:
                return .storageFailure
            }
        }

        do {
            try store.writePIN(newPIN)
            isPINStorageAvailable = true
            hasPIN = true
            resetRateLimitState()
            return .success
        } catch {
            return .storageFailure
        }
    }

    func removePIN(currentPIN: String) -> PINMutationResult {
        guard hasPIN else { return .success }
        switch verifyCurrentPIN(currentPIN) {
        case .success:
            do {
                try store.deletePIN()
                isPINStorageAvailable = true
                hasPIN = false
                resetRateLimitState()
                return .success
            } catch {
                return .storageFailure
            }
        case .incorrectCurrentPIN:
            return .incorrectCurrentPIN
        case let .lockedOut(until):
            return .lockedOut(until: until)
        default:
            return .storageFailure
        }
    }

    func lock() {
        isUnlocked = false
    }

    static func isValidPIN(_ pin: String) -> Bool {
        (4...6).contains(pin.count) && pin.allSatisfy(\.isNumber)
    }

    private func verifyCurrentPIN(_ candidate: String) -> PINMutationResult {
        switch unlock(withPIN: candidate) {
        case .allowed:
            return .success
        case .denied:
            return .incorrectCurrentPIN
        case let .lockedOut(until):
            return .lockedOut(until: until)
        case .unavailable:
            return .storageFailure
        }
    }

    private func activeLockoutDate() -> Date? {
        guard let lockoutUntil else { return nil }
        if lockoutUntil > now() {
            return lockoutUntil
        }
        self.lockoutUntil = nil
        failedAttempts = 0
        persistRateLimitState()
        return nil
    }

    private func refreshPINStatus() {
        do {
            hasPIN = try store.readPIN()?.isEmpty == false
            isPINStorageAvailable = true
        } catch {
            // Fail closed: an unavailable Keychain must never expose the
            // no-PIN math challenge as an alternate authorization route.
            isPINStorageAvailable = false
            hasPIN = true
        }
    }

    private func restoreRateLimitState() {
        failedAttempts = max(0, legacyDefaults.integer(forKey: failedAttemptsKey))
        let timestamp = legacyDefaults.double(forKey: lockoutUntilKey)
        if timestamp > 0 {
            lockoutUntil = Date(timeIntervalSince1970: timestamp)
        }
        _ = activeLockoutDate()
    }

    private func persistRateLimitState() {
        legacyDefaults.set(failedAttempts, forKey: failedAttemptsKey)
        if let lockoutUntil {
            legacyDefaults.set(lockoutUntil.timeIntervalSince1970, forKey: lockoutUntilKey)
        } else {
            legacyDefaults.removeObject(forKey: lockoutUntilKey)
        }
    }

    private func resetRateLimitState() {
        failedAttempts = 0
        lockoutUntil = nil
        legacyDefaults.removeObject(forKey: failedAttemptsKey)
        legacyDefaults.removeObject(forKey: lockoutUntilKey)
    }

    private func migrateLegacyPINIfNeeded() {
        guard let legacyPIN = legacyDefaults.string(forKey: legacyPINKey),
              Self.isValidPIN(legacyPIN)
        else {
            return
        }

        do {
            if try store.readPIN() == nil {
                try store.writePIN(legacyPIN)
            }
            legacyDefaults.removeObject(forKey: legacyPINKey)
        } catch {
            // Leave the legacy value in place so a future launch can retry safely.
        }
    }
}
