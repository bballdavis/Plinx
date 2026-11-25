@testable import Plinx
import Testing

/// Runs a suite with the app's shared `ContentSafetyGate` unlocked, as if a parent were present, and locks it again
/// afterwards. A few absorbed view models check `ContentSafetyGate.shared` directly for parent-only abilities (the
/// player's subtitle search); everything that goes through `MediaServices.fake` uses its own unrestricted gate.
///
/// Apply it to a `.serialized` suite: the shared gate is process-wide, so the suite's tests must not run alongside
/// each other while one of them changes it.
struct SharedGateParentUnlockedTrait: SuiteTrait, TestScoping {
    var isRecursive: Bool {
        false
    }

    func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void,
    ) async throws {
        let wasUnlocked = await MainActor.run {
            let previous = ContentSafetyGate.shared.isParentUnlocked
            ContentSafetyGate.shared.isParentUnlocked = true
            return previous
        }
        do {
            try await function()
        } catch {
            await MainActor.run { ContentSafetyGate.shared.isParentUnlocked = wasUnlocked }
            throw error
        }
        await MainActor.run { ContentSafetyGate.shared.isParentUnlocked = wasUnlocked }
    }
}

extension SuiteTrait where Self == SharedGateParentUnlockedTrait {
    /// See `SharedGateParentUnlockedTrait`.
    static var sharedGateParentUnlocked: Self {
        Self()
    }
}
