import Foundation
import SwiftUI
import PlinxCore

/// Server-independent fixture for the real Explore tab-content lifecycle.
///
/// This route is reachable only with `--ui-testing` plus the matching
/// `PLINX_UI_TEST_SCREEN` value. It keeps credentials and network access out of
/// the regression test while exercising the production view model, decoder,
/// safety policy, tab mounting boundary, and card rendering.
enum YoutarrExploreUITestBootstrap {
    static let screenName = "youtarrExploreOffline"
    private static let failureModeEnvironmentKey = "PLINX_YOUTARR_FIXTURE_FAILURE"

    static func configuration() -> YoutarrConfiguration? {
        try? YoutarrConfiguration(
            baseURL: URL(string: "https://fixture.invalid")!,
            apiKey: "offline-fixture-key"
        )
    }

    static func client(
        configuration: YoutarrConfiguration
    ) -> YoutarrClient {
        YoutarrClient(
            configuration: configuration,
            session: YoutarrExploreFixtureSession(
                failsInitialLoad: ProcessInfo.processInfo.environment[
                    failureModeEnvironmentKey
                ] == "1"
            )
        )
    }

    static let safetyPolicy = SafetyPolicy.ratingOnly(
        maxMovie: .g,
        maxTV: .tvY,
        allowUnrated: false
    )
}

struct YoutarrExploreUITestHarness: View {
    let configuration: YoutarrConfiguration
    let client: YoutarrClient

    @State private var isExploreActive = false

    var body: some View {
        NavigationStack {
            YoutarrExploreTabContent(
                configuration: configuration,
                safetyPolicy: YoutarrExploreUITestBootstrap.safetyPolicy,
                isActive: isExploreActive,
                client: client
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

private final class YoutarrExploreFixtureSession: YoutarrHTTPSession {
    private let failsInitialLoad: Bool

    init(failsInitialLoad: Bool) {
        self.failsInitialLoad = failsInitialLoad
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else {
            throw YoutarrClientError.invalidResponse
        }
        if failsInitialLoad, url.lastPathComponent == "capabilities" {
            throw URLError(.notConnectedToInternet)
        }

        let data: Data
        switch url.lastPathComponent {
        case "capabilities":
            data = Self.capabilities
        case "channels":
            data = Self.channels
        case "videos":
            data = Self.videos
        default:
            throw YoutarrClientError.notFound
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ) else {
            throw YoutarrClientError.invalidResponse
        }
        return (data, response)
    }

    private static let capabilities = Data(
        """
        {
          "apiVersion": "1",
          "serverVersion": "fixture",
          "role": "request",
          "scopes": ["catalog:read", "requests:read", "video:request"],
          "policy": {
            "autoApproveVideoRequests": false,
            "autoApproveChannelRequests": false,
            "autoApproveDeleteRequests": false,
            "maxRatingLevel": 2,
            "allowUnrated": false,
            "allowedMediaTypes": ["video", "short", "livestream"]
          },
          "features": {
            "catalog": true,
            "requests": true,
            "channelRequests": false,
            "deleteRequests": false,
            "recommendations": false,
            "authenticatedAssets": true
          }
        }
        """.utf8
    )

    private static let channels = Data(
        """
        {
          "data": [{
            "id": 42,
            "channelId": "UC-fixture",
            "title": "Fixture Science",
            "descriptionSummary": "Offline Explore fixture",
            "thumbnailUrl": null,
            "subfolder": null,
            "videoCount": 1,
            "downloadedCount": 0,
            "lastFetchedAt": "2026-07-29T00:00:00.000Z"
          }],
          "pagination": {
            "page": 1,
            "pageSize": 100,
            "total": 1,
            "totalPages": 1,
            "nextCursor": null
          },
          "dataSource": "fixture"
        }
        """.utf8
    )

    private static let videos = Data(
        """
        {
          "data": [{
            "youtubeId": "fixture0001",
            "title": "The Offline Explore Video",
            "thumbnailUrl": null,
            "publishedAt": "2026-07-29T00:00:00.000Z",
            "duration": 120,
            "description": "A deterministic regression fixture.",
            "isDownloaded": false,
            "isRequested": false,
            "requestStatus": null,
            "rating": "TV-Y",
            "channelDatabaseId": 42,
            "channelId": "UC-fixture",
            "channelTitle": "Fixture Science",
            "mediaType": "video"
          }, {
            "youtubeId": "fixturesh01",
            "title": "The Offline Explore Short",
            "thumbnailUrl": null,
            "publishedAt": null,
            "duration": "0:45",
            "description": null,
            "isDownloaded": false,
            "isRequested": false,
            "requestStatus": null,
            "rating": 1,
            "channelDatabaseId": 42,
            "channelId": "UC-fixture",
            "channelTitle": "Fixture Science",
            "mediaType": "short"
          }, {
            "youtubeId": "fixturelv01",
            "title": "The Offline Explore Livestream",
            "thumbnailUrl": null,
            "publishedAt": "2026-07-28T00:00:00.000Z",
            "duration": null,
            "description": null,
            "isDownloaded": false,
            "isRequested": false,
            "requestStatus": null,
            "rating": "TV-Y",
            "channelDatabaseId": 42,
            "channelId": "UC-fixture",
            "channelTitle": "Fixture Science",
            "mediaType": "livestream"
          }],
          "pagination": {
            "page": 1,
            "pageSize": 30,
            "total": 3,
            "totalPages": 1,
            "nextCursor": null
          },
          "dataSource": "fixture",
          "isFullyIndexed": true,
          "lastIndexedAt": "2026-07-29T00:00:00.000Z",
          "indexingHint": null
        }
        """.utf8
    )
}
