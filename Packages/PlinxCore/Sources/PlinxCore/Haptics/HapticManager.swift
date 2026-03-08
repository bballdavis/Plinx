import Foundation

#if canImport(UIKit)
import UIKit
#endif

public protocol HapticManaging: Sendable {
    @MainActor
    func plink()
}

public struct HapticManager: HapticManaging {
    public init() {}

    @MainActor
    public func plink() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
        #else
        // no-op on unsupported platforms
        #endif
    }
}
