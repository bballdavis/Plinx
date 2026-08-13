import Foundation

/// Resolves opt-in live-test credentials exclusively from the test process
/// environment. Credentials must never be copied into a test bundle or read
/// from persistent simulator defaults.
enum LiveTestCredentials {
    static func value(
        named key: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.contains("$(") else {
            return nil
        }
        return value
    }

    static var hasPlexServerAndToken: Bool {
        value(named: "PLINX_PLEX_SERVER_URL") != nil
            && value(named: "PLINX_PLEX_TOKEN") != nil
    }
}
