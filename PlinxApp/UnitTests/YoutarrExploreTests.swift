import XCTest
import PlinxCore
@testable import Plinx

final class YoutarrExploreTests: XCTestCase {
    func test_decodesChannelsContract() throws {
        let response = try JSONDecoder().decode(
            YoutarrChannelsResponse.self,
            from: Data(
                """
                {
                  "data": [{
                    "id": 42,
                    "channelId": "UC-safe",
                    "title": "Science Club",
                    "descriptionSummary": "Experiments",
                    "thumbnailUrl": "https://images.example/channel.jpg",
                    "subfolder": "Learning",
                    "videoCount": 120,
                    "downloadedCount": 9,
                    "lastFetchedAt": "2026-07-25T10:00:00.000Z"
                  }],
                  "pagination": {"page": 1, "pageSize": 30, "total": 1, "totalPages": 1},
                  "dataSource": "cache"
                }
                """.utf8
            )
        )

        XCTAssertEqual(response.data.first?.id, 42)
        XCTAssertEqual(response.data.first?.channelId, "UC-safe")
        XCTAssertEqual(response.data.first?.downloadedCount, 9)
        XCTAssertEqual(response.pagination.totalPages, 1)
        XCTAssertEqual(response.dataSource, "cache")
    }

    func test_decodesVideosContractWithFlexibleRatingAndDuration() throws {
        let response = try JSONDecoder().decode(
            YoutarrVideosResponse.self,
            from: Data(
                """
                {
                  "data": [{
                    "youtubeId": "abcdefghijk",
                    "title": "Safe experiment",
                    "thumbnailUrl": "/external-api/v1/assets/videos/abcdefghijk.jpg",
                    "publishedAt": "2026-07-25T10:00:00.000Z",
                    "duration": 125,
                    "description": "A compact description",
                    "isDownloaded": false,
                    "isRequested": true,
                    "requestStatus": "pending",
                    "rating": 2,
                    "channelId": "UC-safe",
                    "channelTitle": "Science Club",
                    "mediaType": "video"
                  }],
                  "pagination": {"page": 1, "pageSize": 30, "total": 1, "totalPages": 1},
                  "dataSource": "partial_cache",
                  "isFullyIndexed": false,
                  "lastIndexedAt": null,
                  "indexingHint": "server detail is not displayed"
                }
                """.utf8
            )
        )

        XCTAssertEqual(response.data.first?.rating, .level(2))
        XCTAssertEqual(response.data.first?.duration, .seconds(125))
        XCTAssertEqual(response.data.first?.mediaType, "video")
        XCTAssertFalse(response.isFullyIndexed)

        let labeled = try JSONDecoder().decode(
            YoutarrVideoRating.self,
            from: Data(#""TV-Y7""#.utf8)
        )
        XCTAssertEqual(labeled, .label("TV-Y7"))
    }

    func test_channelQueryIsEncodedAndPaginationIsBounded() async throws {
        let session = ExploreMockSession(
            data: Data(
                """
                {
                  "data": [],
                  "pagination": {"page": 1, "pageSize": 100, "total": 0, "totalPages": 0},
                  "dataSource": "cache"
                }
                """.utf8
            )
        )
        let client = try makeClient(session: session)

        _ = try await client.channels(page: 0, pageSize: 500, search: "kids & science")

        let request = try XCTUnwrap(session.lastRequest)
        let components = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
        )
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap {
            item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })
        XCTAssertEqual(components.path, "/family/external-api/v1/channels")
        XCTAssertEqual(query["page"], "1")
        XCTAssertEqual(query["pageSize"], "100")
        XCTAssertEqual(query["search"], "kids & science")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "top-secret")
    }

    func test_videoQueryUsesNumericChannelIdentifier() async throws {
        let session = ExploreMockSession(
            data: Data(
                """
                {
                  "data": [],
                  "pagination": {"page": 2, "pageSize": 20, "total": 0, "totalPages": 0},
                  "dataSource": "cache",
                  "isFullyIndexed": true,
                  "lastIndexedAt": null,
                  "indexingHint": null
                }
                """.utf8
            )
        )
        let client = try makeClient(session: session)

        _ = try await client.videos(channelID: 42, page: 2, pageSize: 20)

        XCTAssertEqual(
            session.lastRequest?.url?.path,
            "/family/external-api/v1/channels/42/videos"
        )
    }

    func test_safetyFilterCombinesServerAndLocalRatingLimits() {
        let policy = YoutarrExploreSafetyPolicy(
            serverPolicy: makeServerPolicy(
                maxRatingLevel: 2,
                allowUnrated: false,
                allowedMediaTypes: ["video", "short", "livestream"]
            ),
            localPolicy: .ratingOnly(
                maxMovie: .pg,
                maxTV: .tvPg,
                allowUnrated: false
            )
        )

        XCTAssertTrue(policy.allows(makeVideo(rating: .level(2), mediaType: "video")))
        XCTAssertTrue(policy.allows(makeVideo(rating: .label("TV-PG"), mediaType: "short")))
        XCTAssertFalse(policy.allows(makeVideo(rating: .level(3), mediaType: "video")))
        XCTAssertFalse(policy.allows(makeVideo(rating: nil, mediaType: "video")))
        XCTAssertFalse(policy.allows(makeVideo(rating: .label("UNKNOWN"), mediaType: "video")))
        XCTAssertFalse(policy.allows(makeVideo(rating: .level(1), mediaType: "podcast")))
    }

    func test_unknownRatingFailsClosedEvenWhenUnratedIsAllowed() {
        let policy = YoutarrExploreSafetyPolicy(
            serverPolicy: makeServerPolicy(
                maxRatingLevel: 4,
                allowUnrated: true,
                allowedMediaTypes: ["video"]
            ),
            localPolicy: .ratingOnly(max: .r, allowUnrated: true)
        )

        XCTAssertTrue(policy.allows(makeVideo(rating: nil, mediaType: "video")))
        XCTAssertFalse(policy.allows(makeVideo(rating: .label("NR"), mediaType: "video")))
        XCTAssertFalse(policy.allows(makeVideo(rating: .level(99), mediaType: "video")))
    }

    func test_missingOrMalformedServerMaximumFailsClosed() {
        for maximum in [nil, 0, 5] as [Int?] {
            let policy = YoutarrExploreSafetyPolicy(
                serverPolicy: makeServerPolicy(
                    maxRatingLevel: maximum,
                    allowUnrated: true,
                    allowedMediaTypes: ["video"]
                ),
                localPolicy: .ratingOnly(max: .r, allowUnrated: true)
            )
            XCTAssertFalse(policy.allows(makeVideo(rating: .level(1), mediaType: "video")))
            XCTAssertFalse(policy.allows(makeVideo(rating: nil, mediaType: "video")))
        }
    }

    func test_exploreVisibilityRequiresEnabledAndConfigured() {
        XCTAssertFalse(
            YoutarrExploreVisibility.shouldShow(isEnabled: false, isConfigured: false)
        )
        XCTAssertFalse(
            YoutarrExploreVisibility.shouldShow(isEnabled: true, isConfigured: false)
        )
        XCTAssertFalse(
            YoutarrExploreVisibility.shouldShow(isEnabled: false, isConfigured: true)
        )
        XCTAssertTrue(
            YoutarrExploreVisibility.shouldShow(isEnabled: true, isConfigured: true)
        )
    }

    func test_assetCredentialsAreConfinedToSameOriginExternalAPI() throws {
        let configuration = try YoutarrConfiguration(
            baseURL: URL(string: "https://family.example:8443/family")!,
            apiKey: "asset-secret"
        )

        switch YoutarrAssetRequestPolicy.route(
            rawURL: "/external-api/v1/assets/channels/42/thumbnail",
            configuration: configuration
        ) {
        case .authenticated(let request):
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "x-api-key"),
                "asset-secret"
            )
            XCTAssertEqual(
                request.url?.path,
                "/family/external-api/v1/assets/channels/42/thumbnail"
            )
        default:
            XCTFail("Expected the server asset URL to preserve the configured base path")
        }

        switch YoutarrAssetRequestPolicy.route(
            rawURL: "https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg",
            configuration: configuration
        ) {
        case .publicURL(let url):
            XCTAssertEqual(url.host, "i.ytimg.com")
        default:
            XCTFail("Expected a credential-free public URL")
        }

        switch YoutarrAssetRequestPolicy.route(
            rawURL: "https://family.example:8443/family/external-api/v1/channels",
            configuration: configuration
        ) {
        case .unavailable:
            break
        default:
            XCTFail("Only the authenticated assets subtree may be loaded")
        }

        switch YoutarrAssetRequestPolicy.route(
            rawURL: "http://public.example/image.jpg",
            configuration: configuration
        ) {
        case .unavailable:
            break
        default:
            XCTFail("Public HTTP images must be rejected")
        }

        switch YoutarrAssetRequestPolicy.route(
            rawURL: "https://tracking.example/pixel.jpg",
            configuration: configuration
        ) {
        case .unavailable:
            break
        default:
            XCTFail("Arbitrary public HTTPS image hosts must be rejected")
        }
    }

    @MainActor
    func test_channelSearchIgnoresAStaleSlowResponse() async throws {
        let configuration = try YoutarrConfiguration(
            baseURL: URL(string: "https://family.example/family")!,
            apiKey: "top-secret"
        )
        let session = ExploreRaceSession()
        let viewModel = YoutarrExploreViewModel(
            configuration: configuration,
            client: YoutarrClient(configuration: configuration, session: session)
        )

        viewModel.searchText = "slow"
        let slowTask = Task { @MainActor in await viewModel.reload() }
        try await Task.sleep(nanoseconds: 25_000_000)
        viewModel.searchText = "fast"
        await viewModel.reload()
        await slowTask.value

        XCTAssertEqual(viewModel.channels.map(\.title), ["fast"])
        XCTAssertEqual(viewModel.phase, .ready)
    }

    @MainActor
    func test_videoSearchIgnoresAStaleSlowResponse() async throws {
        let configuration = try YoutarrConfiguration(
            baseURL: URL(string: "https://family.example/family")!,
            apiKey: "top-secret"
        )
        let capabilities = try JSONDecoder().decode(
            YoutarrCapabilities.self,
            from: ExploreRaceSession.capabilitiesData
        )
        let channel = YoutarrChannel(
            id: 42,
            channelId: "UC-safe",
            title: "Science",
            descriptionSummary: nil,
            thumbnailUrl: nil,
            subfolder: nil,
            videoCount: 2,
            downloadedCount: 0,
            lastFetchedAt: nil
        )
        let session = ExploreRaceSession()
        let viewModel = YoutarrChannelViewModel(
            channel: channel,
            configuration: configuration,
            capabilities: capabilities,
            localSafetyPolicy: .ratingOnly(max: .r, allowUnrated: true),
            client: YoutarrClient(configuration: configuration, session: session)
        )

        viewModel.searchText = "slow"
        let slowTask = Task { @MainActor in await viewModel.reload() }
        try await Task.sleep(nanoseconds: 25_000_000)
        viewModel.searchText = "fast"
        await viewModel.reload()
        await slowTask.value

        XCTAssertEqual(viewModel.videos.map(\.title), ["fast"])
        XCTAssertEqual(viewModel.phase, .ready)
    }

    private func makeClient(session: any YoutarrHTTPSession) throws -> YoutarrClient {
        let configuration = try YoutarrConfiguration(
            baseURL: URL(string: "https://family.example/family")!,
            apiKey: "top-secret"
        )
        return YoutarrClient(configuration: configuration, session: session)
    }

    private func makeServerPolicy(
        maxRatingLevel: Int?,
        allowUnrated: Bool,
        allowedMediaTypes: [String]
    ) -> YoutarrCapabilities.Policy {
        .init(
            autoApproveVideoRequests: false,
            autoApproveChannelRequests: false,
            autoApproveDeleteRequests: false,
            maxRatingLevel: maxRatingLevel,
            allowUnrated: allowUnrated,
            allowedMediaTypes: allowedMediaTypes
        )
    }

    private func makeVideo(
        rating: YoutarrVideoRating?,
        mediaType: String
    ) -> YoutarrVideo {
        .init(
            youtubeId: UUID().uuidString,
            title: "Video",
            thumbnailUrl: nil,
            publishedAt: nil,
            duration: nil,
            description: nil,
            isDownloaded: false,
            isRequested: false,
            requestStatus: nil,
            rating: rating,
            channelId: "UC-safe",
            channelTitle: "Channel",
            mediaType: mediaType
        )
    }
}

private final class ExploreMockSession: YoutarrHTTPSession {
    private let data: Data
    private(set) var lastRequest: URLRequest?

    init(data: Data) {
        self.data = data
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        return (
            data,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

private final class ExploreRaceSession: YoutarrHTTPSession {
    static let capabilitiesData = Data(
        """
        {
          "apiVersion": "1",
          "serverVersion": "1.77.0",
          "role": "view",
          "scopes": ["catalog:read", "requests:read"],
          "policy": {
            "autoApproveVideoRequests": false,
            "autoApproveChannelRequests": false,
            "autoApproveDeleteRequests": false,
            "maxRatingLevel": 4,
            "allowUnrated": true,
            "allowedMediaTypes": ["video"]
          },
          "features": {
            "catalog": true,
            "requests": false,
            "channelRequests": false,
            "deleteRequests": false,
            "recommendations": false,
            "authenticatedAssets": true
          }
        }
        """.utf8
    )

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = try XCTUnwrap(request.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "search" })?
            .value ?? ""
        if query == "slow" {
            try await Task.sleep(nanoseconds: 150_000_000)
        }

        let data: Data
        if url.path.hasSuffix("/capabilities") {
            data = Self.capabilitiesData
        } else if url.path.hasSuffix("/videos") {
            data = Self.videoResponse(title: query)
        } else {
            data = Self.channelResponse(title: query)
        }
        return (
            data,
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }

    private static func channelResponse(title: String) -> Data {
        Data(
            """
            {
              "data": [{
                "id": \(title == "slow" ? 1 : 2),
                "channelId": "UC-\(title)",
                "title": "\(title)",
                "descriptionSummary": null,
                "thumbnailUrl": null,
                "subfolder": null,
                "videoCount": 1,
                "downloadedCount": 0,
                "lastFetchedAt": null
              }],
              "pagination": {"page": 1, "pageSize": 30, "total": 1, "totalPages": 1},
              "dataSource": "cache"
            }
            """.utf8
        )
    }

    private static func videoResponse(title: String) -> Data {
        Data(
            """
            {
              "data": [{
                "youtubeId": "\(title)-video",
                "title": "\(title)",
                "thumbnailUrl": null,
                "publishedAt": null,
                "duration": 60,
                "description": null,
                "isDownloaded": false,
                "isRequested": false,
                "requestStatus": null,
                "rating": "G",
                "channelId": "UC-safe",
                "channelTitle": "Science",
                "mediaType": "video"
              }],
              "pagination": {"page": 1, "pageSize": 30, "total": 1, "totalPages": 1},
              "dataSource": "cache",
              "isFullyIndexed": true,
              "lastIndexedAt": null,
              "indexingHint": null
            }
            """.utf8
        )
    }
}
