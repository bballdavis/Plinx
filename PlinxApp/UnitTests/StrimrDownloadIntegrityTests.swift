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

    func test_acceptsResumedDownloadWhenContentRangeMatchesAssembledFile() throws {
        try DownloadIntegrityValidator.validate(
            response: response(
                status: 206,
                contentLength: 400,
                additionalHeaders: ["Content-Range": "bytes 600-999/1000"]
            ),
            stagedFileSize: 1_000
        )
    }

    func test_rejectsResumedDownloadWhenContentRangeTotalDoesNotMatchFile() {
        XCTAssertThrowsError(
            try DownloadIntegrityValidator.validate(
                response: response(
                    status: 206,
                    contentLength: 400,
                    additionalHeaders: ["Content-Range": "bytes 600-999/1200"]
                ),
                stagedFileSize: 1_000
            )
        ) { error in
            XCTAssertEqual(error as? DownloadIntegrityFailure, .contentLengthMismatch)
        }
    }

    func test_acceptsResumedDownloadWhenServerOmitsCompleteSize() throws {
        try DownloadIntegrityValidator.validate(
            response: response(status: 206, contentLength: 400),
            stagedFileSize: 1_000
        )
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
        XCTAssertEqual(transcoded["autoAdjustQuality"], "0")
        XCTAssertEqual(transcoded["directPlay"], "0")
        XCTAssertEqual(transcoded["directStream"], "0")
        XCTAssertEqual(transcoded["directStreamAudio"], "0")
        XCTAssertEqual(transcoded["audioChannelCount"], "2")

        let original = queryDictionary(for: .original)
        XCTAssertNil(original["videoBitrate"])
        XCTAssertNil(original["peakBitrate"])
        XCTAssertNil(original["videoResolution"])
        XCTAssertEqual(original["directPlay"], "1")
        XCTAssertEqual(original["directStream"], "1")
    }

    func test_spaceSavingsPolicyKeepsReducedQualityWhenVideoEstimateIsSmaller() {
        let resolution = DownloadSpaceSavingsPolicy.resolve(
            requestedQuality: .megabits3_720p,
            sourceFileSize: 1_000_000_000,
            duration: 600
        )

        XCTAssertEqual(resolution.effectiveQuality, .megabits3_720p)
        XCTAssertEqual(resolution.estimatedOutputBytes, 244_188_000)
        XCTAssertEqual(resolution.reason, .requested)

        let query = queryDictionary(for: resolution.effectiveQuality)
        XCTAssertEqual(query["videoBitrate"], "3000")
        XCTAssertEqual(query["videoResolution"], "1280x720")
    }

    func test_spaceSavingsPolicyUsesOriginalWhenVideoEstimateCannotSaveSpace() {
        let resolution = DownloadSpaceSavingsPolicy.resolve(
            requestedQuality: .megabits3_720p,
            sourceFileSize: 1_000_000_000,
            duration: 5_400
        )

        XCTAssertEqual(resolution.effectiveQuality, .original)
        XCTAssertEqual(resolution.reason, .originalIsSmaller)
    }

    func test_spaceSavingsPolicyRequiresTwentyPercentEstimatedSavings() {
        XCTAssertTrue(
            DownloadSpaceSavingsPolicy.hasMinimumSavings(
                candidateSize: 800_000_000,
                sourceFileSize: 1_000_000_000
            )
        )
        XCTAssertFalse(
            DownloadSpaceSavingsPolicy.hasMinimumSavings(
                candidateSize: 800_000_001,
                sourceFileSize: 1_000_000_000
            )
        )
    }

    func test_spaceSavingsPolicyExplainsInsufficientEstimatedSavings() {
        let resolution = DownloadSpaceSavingsPolicy.resolve(
            requestedQuality: .megabits3_720p,
            sourceFileSize: 500_000_000,
            duration: 1_000
        )

        XCTAssertEqual(resolution.estimatedOutputBytes, 406_980_000)
        XCTAssertEqual(resolution.effectiveQuality, .original)
        XCTAssertEqual(resolution.reason, .insufficientSavings)
    }

    func test_spaceSavingsPolicyReplacesOversizedCompletedTranscode() {
        XCTAssertTrue(
            DownloadSpaceSavingsPolicy.shouldReplaceTranscode(
                downloadedFileSize: 1_000_000_000,
                sourceFileSize: 900_000_000,
                effectiveQuality: .megabits3_720p
            )
        )
        XCTAssertFalse(
            DownloadSpaceSavingsPolicy.shouldReplaceTranscode(
                downloadedFileSize: 700_000_000,
                sourceFileSize: 1_000_000_000,
                effectiveQuality: .original
            )
        )
        XCTAssertFalse(
            DownloadSpaceSavingsPolicy.shouldReplaceTranscode(
                downloadedFileSize: 799_000_000,
                sourceFileSize: 1_000_000_000,
                effectiveQuality: .megabits3_720p
            )
        )
    }

    func test_reducedDownloadProfileUsesDocumentedTargetAndUniqueSession() {
        XCTAssertTrue(PlexDownloadQueueRepository.clientProfileExtra.contains("add-transcode-target("))
        XCTAssertTrue(PlexDownloadQueueRepository.clientProfileExtra.contains("container=mkv"))
        XCTAssertTrue(PlexDownloadQueueRepository.clientProfileExtra.contains("videoCodec=h264"))
        XCTAssertTrue(PlexDownloadQueueRepository.clientProfileExtra.contains("audioCodec=aac"))
        XCTAssertTrue(PlexDownloadQueueRepository.clientProfileExtra.contains("audio.bitrate&value=192"))
        XCTAssertFalse(PlexDownloadQueueRepository.clientProfileExtra.contains("append-transcode-target-codec"))
        XCTAssertNotEqual(
            PlexDownloadQueueRepository.plexSessionIdentifier(for: "one"),
            PlexDownloadQueueRepository.plexSessionIdentifier(for: "two")
        )
    }

    func test_plexPartDecodesSourceFileSize() throws {
        let payload = Data(
            #"{"id":1,"key":"/library/parts/1/file.mkv","size":987654321}"#.utf8
        )

        let part = try JSONDecoder().decode(PlexPart.self, from: payload)
        XCTAssertEqual(part.size, 987_654_321)
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

    func test_downloadDecisionDecodesAndValidatesForcedProfile() throws {
        let payload = Data(
            """
            {
              "MediaContainer": {
                "directPlayDecisionCode": 3000,
                "transcodeDecisionCode": 1001,
                "Metadata": [{
                  "Media": [{
                    "selected": true,
                    "protocol": "http",
                    "Part": [{
                      "selected": true,
                      "decision": "transcode",
                      "protocol": "http",
                      "Stream": [
                        {"streamType": 1, "codec": "h264", "decision": "transcode", "bitrate": 3000, "width": 1280, "height": 720},
                        {"streamType": 2, "codec": "aac", "decision": "transcode", "bitrate": 192, "channels": 2}
                      ]
                    }]
                  }]
                }]
              }
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(PlexDownloadDecisionResponse.self, from: payload)
        XCTAssertNoThrow(
            try PlexDownloadDecisionValidator.validate(
                response.mediaContainer.decision,
                profile: .init(videoBitrateKbps: 3_000, width: 1280, height: 720)
            )
        )
    }

    func test_downloadDecisionRejectsDirectPlay() throws {
        let part = PlexDownloadDecisionPart(
            selected: true,
            decision: "transcode",
            protocolName: "http",
            streams: [
                .init(streamType: 1, codec: "h264", decision: "transcode", bitrate: 3_001, channels: nil, width: 1280, height: 720),
                .init(streamType: 2, codec: "aac", decision: "transcode", bitrate: 192, channels: 2, width: nil, height: nil),
            ]
        )
        let media = PlexDownloadDecisionMedia(selected: true, protocolName: "http", parts: [part])
        let decision = PlexDownloadDecision(
            directPlayDecisionCode: 1000,
            transcodeDecisionCode: 1001,
            media: [media]
        )

        XCTAssertThrowsError(
            try PlexDownloadDecisionValidator.validate(
                decision,
                profile: .init(videoBitrateKbps: 3_000, width: 1280, height: 720)
            )
        ) { error in
            XCTAssertEqual(error as? PlexDownloadProfileValidationFailure, .directPlaySelected)
        }
    }

    func test_downloadDecisionRejectsVideoAboveRequestedBitrate() throws {
        let part = PlexDownloadDecisionPart(
            selected: true,
            decision: "transcode",
            protocolName: "http",
            streams: [
                .init(streamType: 1, codec: "h264", decision: "transcode", bitrate: 3_001, channels: nil, width: 1280, height: 720),
                .init(streamType: 2, codec: "aac", decision: "transcode", bitrate: 192, channels: 2, width: nil, height: nil),
            ]
        )
        let decision = PlexDownloadDecision(
            directPlayDecisionCode: 3000,
            transcodeDecisionCode: 1001,
            media: [.init(selected: true, protocolName: "http", parts: [part])]
        )

        XCTAssertThrowsError(
            try PlexDownloadDecisionValidator.validate(
                decision,
                profile: .init(videoBitrateKbps: 3_000, width: 1280, height: 720)
            )
        ) { error in
            XCTAssertEqual(error as? PlexDownloadProfileValidationFailure, .videoBitrateExceeded)
        }
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
        object.removeValue(forKey: "effectiveQuality")
        object.removeValue(forKey: "sourceFileSize")
        object.removeValue(forKey: "estimatedOutputBytes")
        object.removeValue(forKey: "qualityResolutionReason")
        object.removeValue(forKey: "deliveryDecision")
        object.removeValue(forKey: "remoteReference")

        let decoded = try JSONDecoder().decode(
            DownloadItem.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(decoded.id, "legacy")
        XCTAssertNil(decoded.requestedQuality)
        XCTAssertNil(decoded.effectiveQuality)
        XCTAssertNil(decoded.sourceFileSize)
        XCTAssertNil(decoded.estimatedOutputBytes)
        XCTAssertNil(decoded.qualityResolutionReason)
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
        contentType: String? = nil,
        additionalHeaders: [String: String] = [:]
    ) -> HTTPURLResponse {
        var headers = additionalHeaders
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
