import Foundation
import PlinxCore

/// Opt-in live-test wiring. It is unreachable during normal app launches and
/// keeps test credentials in the test process environment rather than source.
enum YoutarrLiveTestBootstrap {
    static let screenName = "youtarrExploreLive"
    private static let seedSavedConfigurationKey =
        "PLINX_YOUTARR_SEED_SAVED_CONFIGURATION"

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

    /// Seeds the real configuration store only for the explicitly mutating
    /// main-tab smoke test. This lets that test cover RootTabView's normal
    /// configuration path without embedding a credential in source.
    static func seedSavedConfigurationIfNeeded(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) {
        guard arguments.contains("--ui-testing"),
              environment[seedSavedConfigurationKey] == "1",
              let configuration = configuration(
                arguments: arguments,
                environment: environment
              ) else {
            return
        }
        do {
            try YoutarrConfigurationStore(defaults: defaults).save(
                baseURL: configuration.baseURL.absoluteString,
                apiKey: configuration.apiKey
            )
            defaults.set(true, forKey: YoutarrExplorePreference.storageKey)
        } catch {
            assertionFailure("Unable to seed the Youtarr live-test configuration.")
        }
    }
}
