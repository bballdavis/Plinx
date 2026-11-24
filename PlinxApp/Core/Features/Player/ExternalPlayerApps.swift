import Foundation

/// Plinx never hands playback to another app: doing so would bypass content
/// checks and the playback volume cap (docs/security/privacy-and-safety.md).
/// Every external player therefore reports as unavailable and cannot launch.
enum ExternalPlayerApps {
    static func open(_: ExternalLaunchRequest) async -> Bool {
        false
    }

    static func isInstalled(_: ExternalPlayerID, platform _: Platform = .current) -> Bool {
        false
    }
}
