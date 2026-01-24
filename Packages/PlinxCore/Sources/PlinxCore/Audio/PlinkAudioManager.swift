import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

public protocol PlinkAudioManaging: Sendable {
    func playPlink()
}

public final class PlinkAudioManager: PlinkAudioManaging {
    public init() {}

    public func playPlink() {
        #if canImport(AVFoundation)
        // Placeholder: wire to bundled Plink.caf in app target
        #else
        // no-op on unsupported platforms
        #endif
    }
}
