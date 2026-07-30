import XCTest
import UIKit
import PlinxCore
@testable import Plinx

/// Real-network contract checks for a dedicated, parent-controlled Youtarr.
/// They skip unless PLINX_YOUTARR_LIVE=1 is injected into the simulator.
final class YoutarrLiveSmokeTests: XCTestCase {
    func test_liveCatalogIsRequestableVisibleAndUsesLandscapeProxyArtwork() async throws {
        let configuration = try liveConfiguration()
        let client = YoutarrClient(configuration: configuration)

        let capabilities = try await client.capabilities()
        XCTAssertEqual(capabilities.apiVersion, "1")
        XCTAssertTrue(YoutarrCatalogCapabilityPolicy.canBrowse(capabilities))

        let response = try await client.catalogVideos(pageSize: 10)
        let videos = response.data
        XCTAssertFalse(videos.isEmpty, "The live fixture needs at least one requestable video.")
        XCTAssertTrue(videos.allSatisfy { !$0.isDownloaded && !$0.isRequested })
        XCTAssertTrue(videos.allSatisfy { $0.channelDatabaseId != nil })

        let safetyPolicy = YoutarrExploreSafetyPolicy(
            serverPolicy: capabilities.policy,
            localPolicy: liveSafetyPolicy()
        )
        XCTAssertFalse(
            videos.filter(safetyPolicy.allows).isEmpty,
            "The live channel ratings must overlap the profile rating used by this smoke test."
        )

        let thumbnail = try XCTUnwrap(videos.first?.thumbnailUrl)
        guard case .authenticated(let request) = YoutarrAssetRequestPolicy.route(
            rawURL: thumbnail,
            configuration: configuration
        ) else {
            return XCTFail("Expected an authenticated Youtarr asset-proxy request.")
        }
        let (data, urlResponse) = try await YoutarrHTTPSessions.noRedirects.data(for: request)
        XCTAssertTrue((200...299).contains(try XCTUnwrap(urlResponse as? HTTPURLResponse).statusCode))
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertGreaterThan(image.size.width, image.size.height)
    }

    func test_liveRequestsEndpointDecodes() async throws {
        let configuration = try liveConfiguration()
        let response = try await YoutarrClient(configuration: configuration)
            .requests(page: 1, pageSize: 10)
        XCTAssertGreaterThanOrEqual(response.pagination.total, response.data.count)
    }

    func test_liveVideoRequestRoundTrip_whenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["PLINX_YOUTARR_LIVE_WRITE"] == "1" else {
            throw XCTSkip("Live request writes require PLINX_YOUTARR_LIVE_WRITE=1.")
        }
        let configuration = try liveConfiguration()
        let client = YoutarrClient(configuration: configuration)
        let catalog = try await client.catalogVideos(pageSize: 10)
        let video = try XCTUnwrap(
            catalog.data.first(where: { $0.channelDatabaseId != nil })
        )
        let response = try await client.requestVideo(
            youtubeID: video.youtubeId,
            channelID: try XCTUnwrap(video.channelDatabaseId)
        )
        XCTAssertTrue(
            [.created, .duplicate, .alreadyDownloaded].contains(response.outcome)
        )
    }

    private func liveConfiguration() throws -> YoutarrConfiguration {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PLINX_YOUTARR_LIVE"] == "1",
              let rawURL = environment["PLINX_YOUTARR_URL"],
              let baseURL = URL(string: rawURL),
              let apiKey = environment["PLINX_YOUTARR_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("Live Youtarr smoke tests are opt-in.")
        }
        return try YoutarrConfiguration(baseURL: baseURL, apiKey: apiKey)
    }

    private func liveSafetyPolicy() -> SafetyPolicy {
        let rawRating = ProcessInfo.processInfo.environment[
            "PLINX_YOUTARR_MAX_TV_RATING"
        ] ?? "TV-Y"
        return .ratingOnly(
            maxMovie: .g,
            maxTV: PlinxRating.from(contentRating: rawRating) ?? .tvY,
            allowUnrated: false
        )
    }
}
