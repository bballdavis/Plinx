import CryptoKit
import XCTest
@testable import Plinx

final class YoutarrContractFixtureTests: XCTestCase {
    private struct Contract: Decodable {
        struct RepresentativeProfile: Decodable {
            let basis: String
            let channelCount: Int
            let catalogFirstPageCount: Int
            let mediaTypeCounts: [String: Int]
            let commonRatings: [String]
            let typicalNullFields: [String]
            let shortsMayOmitPublishedAt: Bool
            let artworkUsesAuthenticatedSameOriginPaths: Bool
        }

        struct UnknownEnumSamples: Decodable {
            let request: YoutarrRequest
            let videoRequestResponse: YoutarrVideoRequestResponse
        }

        let fixtureVersion: Int
        let representativeProfile: RepresentativeProfile
        let capabilities: YoutarrCapabilities
        let channelsPage: YoutarrChannelsResponse
        let error: YoutarrErrorEnvelope
        let requests: [YoutarrRequest]
        let catalogPage: YoutarrVideosResponse
        let catalogNextPage: YoutarrVideosResponse
        let videoDetail: YoutarrVideoDetail
        let sparseVideoDetail: YoutarrVideoDetail
        let videoRequestResponses: [YoutarrVideoRequestResponse]
        let unknownEnumSamples: UnknownEnumSamples
    }

    func test_decodesCanonicalYoutarrV1Contract() throws {
        let contract = try JSONDecoder().decode(Contract.self, from: fixtureData())

        XCTAssertEqual(contract.fixtureVersion, 4)
        XCTAssertEqual(contract.capabilities.apiVersion, "1")
        XCTAssertEqual(contract.error.error.code, "not_found")
        XCTAssertEqual(contract.channelsPage.data.count, 4)
        XCTAssertEqual(
            Set(contract.catalogPage.data.map(\.mediaType)),
            Set(["video", "short", "livestream"])
        )
        XCTAssertNotNil(contract.catalogPage.pagination.nextCursor)
        XCTAssertNil(contract.catalogNextPage.pagination.nextCursor)
        XCTAssertEqual(contract.catalogPage.data[0].duration, .seconds(120))
        XCTAssertEqual(contract.catalogPage.data[1].duration, .seconds(45))
        XCTAssertEqual(contract.catalogPage.data[2].duration, .seconds(3_600))
        XCTAssertNotNil(contract.videoDetail.metadata)
        XCTAssertNil(contract.sparseVideoDetail.metadata)
        XCTAssertEqual(
            contract.videoRequestResponses.map(\.outcome),
            [.created, .duplicate, .alreadyDownloaded]
        )
    }

    func test_representativeCatalogMatchesSanitizedLiveShapeProfile() throws {
        let contract = try JSONDecoder().decode(Contract.self, from: fixtureData())
        let profile = contract.representativeProfile
        let catalog = contract.catalogPage.data
        let mediaTypeCounts = Dictionary(grouping: catalog, by: \.mediaType)
            .mapValues(\.count)

        XCTAssertEqual(profile.basis, "sanitized-live-shape")
        XCTAssertEqual(contract.channelsPage.data.count, profile.channelCount)
        XCTAssertEqual(catalog.count, profile.catalogFirstPageCount)
        XCTAssertEqual(mediaTypeCounts, profile.mediaTypeCounts)
        XCTAssertEqual(
            Set(catalog.compactMap { $0.rating?.displayValue }),
            Set(profile.commonRatings)
        )
        XCTAssertTrue(catalog.allSatisfy { $0.description == nil && $0.requestStatus == nil })
        XCTAssertTrue(catalog.allSatisfy { $0.duration != nil })
        XCTAssertTrue(
            catalog.filter { $0.mediaType == "short" }.allSatisfy { $0.publishedAt == nil }
        )
        XCTAssertEqual(Set(profile.typicalNullFields), Set(["description", "requestStatus"]))
        XCTAssertTrue(profile.shortsMayOmitPublishedAt)
        XCTAssertTrue(profile.artworkUsesAuthenticatedSameOriginPaths)
        XCTAssertTrue(catalog.allSatisfy {
            $0.thumbnailUrl == "/external-api/v1/assets/videos/\($0.youtubeId)/thumbnail"
        })
    }

    func test_unknownRequestEnumsDecodeButAreNotPresentableVideoRequests() throws {
        let samples = try JSONDecoder().decode(Contract.self, from: fixtureData()).unknownEnumSamples

        XCTAssertEqual(samples.request.type, .unknown("future_request_type"))
        XCTAssertEqual(samples.request.status, .unknown("future_status"))
        XCTAssertNil(samples.request.videoYoutubeID)
        XCTAssertFalse(samples.request.status.isActive)
        XCTAssertEqual(samples.videoRequestResponse.outcome, .unknown("future_outcome"))
    }

    func test_vendoredFixtureMatchesPublishedChecksum() throws {
        let digest = SHA256.hash(data: try fixtureData())
            .map { String(format: "%02x", $0) }
            .joined()
        let sums = try String(
            contentsOf: fixtureURL(named: "SHA256SUMS", extension: "txt"),
            encoding: .utf8
        )
        let published = try XCTUnwrap(sums.split(whereSeparator: \.isWhitespace).first.map(String.init))

        XCTAssertEqual(digest, published)
    }

    private func fixtureData() throws -> Data {
        try Data(contentsOf: fixtureURL(named: "contract", extension: "json"))
    }

    private func fixtureURL(named name: String, extension fileExtension: String? = nil) throws -> URL {
        let bundle = Bundle(for: Self.self)
        return try XCTUnwrap(
            bundle.url(
                forResource: name,
                withExtension: fileExtension,
                subdirectory: "YoutarrExternalAPIV1"
            ) ?? bundle.url(forResource: name, withExtension: fileExtension)
        )
    }
}
