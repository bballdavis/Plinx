import Foundation
import PlinxCore

/// Opt-in live-test wiring. It is unreachable during normal app launches and
/// keeps test credentials in the test process environment rather than source.
enum YoutarrLiveTestBootstrap {
    static let screenName = "youtarrExploreLive"
    private static let mainTabEnvironmentKey = "PLINX_YOUTARR_LIVE_MAIN_TAB"

    static func configuration(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> YoutarrConfiguration? {
        guard arguments.contains("--ui-testing"),
              environment["PLINX_YOUTARR_LIVE"] == "1",
              let rawURL = environment["PLINX_YOUTARR_URL"],
              let baseURL = URL(string: rawURL),
              let apiKey = environment["PLINX_YOUTARR_API_KEY"],
              !apiKey.isEmpty else {
            return nil
        }
        return try? YoutarrConfiguration(baseURL: baseURL, apiKey: apiKey)
    }

    static func safetyPolicy(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SafetyPolicy {
        let maxTVRating = PlinxRating.from(
            contentRating: environment["PLINX_YOUTARR_MAX_TV_RATING"] ?? "TV-Y"
        ) ?? .tvY
        return .ratingOnly(
            maxMovie: .g,
            maxTV: maxTVRating,
            allowUnrated: false
        )
    }

    /// Process-only configuration for the opt-in RootTab live smoke test.
    /// This deliberately never writes the simulator's production defaults or
    /// Keychain, so a test key cannot alter a family's saved connection.
    static func mainTabConfiguration(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> YoutarrConfiguration? {
        guard arguments.contains("--ui-testing"),
              environment[mainTabEnvironmentKey] == "1" else {
            return nil
        }
        return configuration(arguments: arguments, environment: environment)
    }
}
