import Foundation
import SwiftUI
import PlinxCore

/// Synthetic HTTP coverage for the production Youtarr client and Explore UI.
///
/// The companion server mounts Youtarr's real external API router over its
/// canonical sanitized dataset. Only its loopback address and non-secret test
/// key enter the app process.
enum YoutarrExploreUITestBootstrap {
    static let screenName = "youtarrExploreSynthetic"
    static let baseURLEnvironmentKey = "PLINX_YOUTARR_SYNTHETIC_URL"
    static let apiKeyEnvironmentKey = "PLINX_YOUTARR_SYNTHETIC_API_KEY"

    static func configuration(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> YoutarrConfiguration? {
        guard let rawURL = environment[baseURLEnvironmentKey],
              let baseURL = URL(string: rawURL),
              let apiKey = environment[apiKeyEnvironmentKey],
              !apiKey.isEmpty else {
            return nil
        }
        return try? YoutarrConfiguration(baseURL: baseURL, apiKey: apiKey)
    }

    static let safetyPolicy = SafetyPolicy.ratingOnly(
        maxMovie: .pg,
        maxTV: .tvY7,
        allowUnrated: true
    )
}

struct YoutarrExploreUITestHarness: View {
    let configuration: YoutarrConfiguration

    @State private var isExploreActive = false

    var body: some View {
        NavigationStack {
            YoutarrExploreTabContent(
                configuration: configuration,
                safetyPolicy: YoutarrExploreUITestBootstrap.safetyPolicy,
                isActive: isExploreActive
            )
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 20) {
                Button {
                    isExploreActive = false
                } label: {
                    Label("Home", systemImage: "house")
                        .frame(minWidth: 120, minHeight: 48)
                }
                .accessibilityIdentifier("main.tab.home.fixture")

                Button {
                    isExploreActive = true
                } label: {
                    Label("Explore", systemImage: "sparkles")
                        .frame(minWidth: 120, minHeight: 48)
                }
                .accessibilityIdentifier("main.tab.explore.fixture")
            }
        }
    }
}
