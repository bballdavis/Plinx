@testable import Plinx
import XCTest

final class StrimrDownloadIntegrityTests: XCTestCase {
    func test_acceptsSuccessfulNonEmptyDownload() throws {
        try DownloadIntegrityValidator.validate(
            response: response(status: 200, contentLength: 4),
            stagedFileSize: 4
        )
    }

    func test_acceptsSuccessfulDownloadWithUnknownLength() throws {
        try DownloadIntegrityValidator.validate(
            response: response(status: 200),
            stagedFileSize: 4
        )
    }

    func test_rejectsMissingOrNonHTTPResponse() {
        XCTAssertThrowsError(
            try DownloadIntegrityValidator.validate(response: nil, stagedFileSize: 4)
        ) { error in
            XCTAssertEqual(error as? DownloadIntegrityFailure, .invalidResponse)
        }
    }

    func test_rejectsUnsuccessfulHTTPResponses() {
        for status in [401, 404, 500] {
            XCTAssertThrowsError(
                try DownloadIntegrityValidator.validate(
                    response: response(status: status, contentLength: 4),
                    stagedFileSize: 4
                )
            ) { error in
                XCTAssertEqual(error as? DownloadIntegrityFailure, .unsuccessfulStatus)
            }
        }
    }

    func test_rejectsEmptyDownload() {
        XCTAssertThrowsError(
            try DownloadIntegrityValidator.validate(
                response: response(status: 200, contentLength: 0),
                stagedFileSize: 0
            )
        ) { error in
            XCTAssertEqual(error as? DownloadIntegrityFailure, .emptyFile)
        }
    }

    func test_rejectsContentLengthMismatch() {
        XCTAssertThrowsError(
            try DownloadIntegrityValidator.validate(
                response: response(status: 200, contentLength: 8),
                stagedFileSize: 4
            )
        ) { error in
            XCTAssertEqual(error as? DownloadIntegrityFailure, .contentLengthMismatch)
        }
    }

    func test_rejectsTextAndStructuredErrorPayloads() {
        for contentType in ["text/html", "application/json", "application/xml"] {
            XCTAssertThrowsError(
                try DownloadIntegrityValidator.validate(
                    response: response(status: 200, contentLength: 4, contentType: contentType),
                    stagedFileSize: 4
                )
            ) { error in
                XCTAssertEqual(error as? DownloadIntegrityFailure, .unexpectedContentType)
            }
        }
    }

    func test_downloadQualityPresetsDecodeAndMapToQueueParameters() throws {
        let encoded = Data(#""megabits20_1080p""#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(DownloadQuality.self, from: encoded), .megabits20_1080p)
        XCTAssertEqual(DownloadQuality.allCases.count, 9)
        let expectedProfiles: [DownloadQuality: DownloadTranscodeProfile] = [
            .megabits20_1080p: .init(videoBitrateKbps: 20_000, width: 1920, height: 1080),
            .megabits12_1080p: .init(videoBitrateKbps: 12_000, width: 1920, height: 1080),
            .megabits10_720p: .init(videoBitrateKbps: 10_000, width: 1280, height: 720),
            .megabits4_720p: .init(videoBitrateKbps: 4_000, width: 1280, height: 720),
            .megabits3_720p: .init(videoBitrateKbps: 3_000, width: 1280, height: 720),
            .megabits2_720p: .init(videoBitrateKbps: 2_000, width: 1280, height: 720),
            .kilobits1500_480p: .init(videoBitrateKbps: 1_500, width: 848, height: 480),
            .kilobits720_328p: .init(videoBitrateKbps: 720, width: 640, height: 360),
        ]
        for (quality, profile) in expectedProfiles {
            XCTAssertEqual(quality.transcodeProfile, profile)
            let query = queryDictionary(for: quality)
            XCTAssertEqual(query["videoBitrate"], String(profile.videoBitrateKbps))
            XCTAssertEqual(query["peakBitrate"], String(profile.videoBitrateKbps))
            XCTAssertEqual(query["videoResolution"], profile.resolution)
        }

        let transcoded = queryDictionary(for: .kilobits1500_480p)
        XCTAssertEqual(transcoded["keys"], "/library/metadata/123")
        XCTAssertEqual(transcoded["videoBitrate"], "1500")
        XCTAssertEqual(transcoded["peakBitrate"], "1500")
        XCTAssertEqual(transcoded["videoResolution"], "848x480")

        let original = queryDictionary(for: .original)
        XCTAssertNil(original["videoBitrate"])
        XCTAssertNil(original["peakBitrate"])
        XCTAssertNil(original["videoResolution"])
        XCTAssertEqual(original["directPlay"], "1")
        XCTAssertEqual(original["directStream"], "1")
    }

    func test_downloadQueueItemDecodesOfficialProcessingShape() throws {
        let payload = Data(
            """
            {
              "id": 1,
              "queueId": 2,
              "key": "/library/metadata/3",
              "status": "processing",
              "DecisionResult": {
                "generalDecisionCode": 1001,
                "generalDecisionText": "Conversion OK.",
                "directPlayDecisionCode": 3001,
                "directPlayDecisionText": "Not enough bandwidth.",
                "transcodeDecisionCode": 1001,
                "transcodeDecisionText": "Conversion OK."
              },
              "TranscodeSession": {
                "progress": 42.5,
                "size": 1000,
                "speed": 2.0,
                "error": false,
                "duration": 300000000,
                "protocol": "http",
                "sourceVideoCodec": "hevc",
                "sourceAudioCodec": "aac"
              }
            }
            """.utf8
        )

        let item = try JSONDecoder().decode(PlexDownloadQueueItem.self, from: payload)
        XCTAssertEqual(item.status, .processing)
        XCTAssertEqual(item.queueId, 2)
        XCTAssertEqual(item.decisionResult?.transcodeDecisionCode, 1001)
        XCTAssertEqual(item.transcodeSession?.progress, 42.5)
        XCTAssertEqual(item.transcodeSession?.protocolName, "http")
    }

    func test_downloadItemDecodesIndexWrittenBeforeQueueFields() throws {
        let original = DownloadItem(
            id: "legacy",
            status: .queued,
            progress: 0,
            bytesWritten: 0,
            totalBytes: 0,
            taskIdentifier: nil,
            errorMessage: nil,
            metadata: DownloadedMediaMetadata(
                ratingKey: "123",
                guid: "plex://movie/123",
                type: .movie,
                title: "Legacy",
                summary: nil,
                genres: [],
                year: 2024,
                duration: 100,
                contentRating: "G",
                studio: nil,
                tagline: nil,
                parentRatingKey: nil,
                grandparentRatingKey: nil,
                grandparentTitle: nil,
                parentTitle: nil,
                parentIndex: nil,
                index: nil,
                posterFileName: nil,
                videoFileName: "video.mp4",
                fileSize: nil,
                createdAt: Date(timeIntervalSince1970: 1)
            )
        )
        let encoded = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "preparationProgress")
        object.removeValue(forKey: "requestedQuality")
        object.removeValue(forKey: "deliveryDecision")
        object.removeValue(forKey: "remoteReference")

        let decoded = try JSONDecoder().decode(
            DownloadItem.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(decoded.id, "legacy")
        XCTAssertNil(decoded.requestedQuality)
        XCTAssertNil(decoded.remoteReference)
    }

    private func queryDictionary(for quality: DownloadQuality) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: PlexDownloadQueueRepository
                .addQueryItems(ratingKey: "123", quality: quality)
                .compactMap { item in item.value.map { (item.name, $0) } }
        )
    }

    private func response(
        status: Int,
        contentLength: Int64? = nil,
        contentType: String? = nil
    ) -> HTTPURLResponse {
        var headers: [String: String] = [:]
        if let contentLength {
            headers["Content-Length"] = String(contentLength)
        }
        if let contentType {
            headers["Content-Type"] = contentType
        }
        return HTTPURLResponse(
            url: URL(string: "https://example.test/video")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers.isEmpty ? nil : headers
        )!
    }
}
