import SwiftUI

private struct SafetyPolicyKey: EnvironmentKey {
    static let defaultValue = SafetyPolicy.ratingOnly()
}

public extension EnvironmentValues {
    var safetyPolicy: SafetyPolicy {
        get { self[SafetyPolicyKey.self] }
        set { self[SafetyPolicyKey.self] = newValue }
    }
}
