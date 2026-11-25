@testable import Plinx
import XCTest

/// Download integrity on the absorbed stack: the strict check of a finished transfer
/// (`DownloadIntegrityValidator`), the 20 percent space-savings rule
/// (`DownloadSpaceSavingsPolicy`), the mapping of pre-fork Plinx download-quality settings
/// to `TranscodeQualityPreset`, and how a pre-fork download index entry is read back.
final class DownloadIntegrityTests: XCTestCase {
    // MARK: - Pre-fork ownership and index state

    func test_downloadAccessScopeRoundTripsWithBothIdentityDimensions() throws {
        let scope = DownloadAccessScope(
            serverIdentifier: "server-a",
            accessScopeIdentifier: "profile-a"
        )

        let encoded = try JSONEncoder().encode(scope)
        XCTAssertEqual(try JSONDecoder().decode(DownloadAccessScope.self, from: encoded), scope)
    }

    func test_downloadAccessScopeMatchesThePlexOwnerItWasRecordedFor() {
        let owner = MediaOwner(server: ServerIdentity(provider: .plex, id: "server-a"), userID: "profile-a")

        XCTAssertEqual(
            DownloadAccessScope(owner: owner),
            DownloadAccessScope(serverIdentifier: "server-a", accessScopeIdentifier: "profile-a")
        )
    }

    func test_downloadIndexFailureStatesDoNotPermitPersistenceOrOwnershipMigration() {
        XCTAssertTrue(DownloadPersistedIndexState.missing.permitsPersistence)
        XCTAssertTrue(DownloadPersistedIndexState.loaded.permitsOwnershipMigration)
        XCTAssertFalse(DownloadPersistedIndexState.unreadable.permitsPersistence)
        XCTAssertFalse(DownloadPersistedIndexState.corrupt.permitsOwnershipMigration)
        XCTAssertFalse(DownloadPersistedIndexState.missing.permitsOwnershipMigration)
        XCTAssertFalse(DownloadPersistedIndexState.unreadable.permitsOwnershipMigration)
        XCTAssertFalse(DownloadPersistedIndexState.corrupt.permitsPersistence)
    }

    // MARK: - Finished-transfer validation

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
            stagedFileSize: 1000
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
                stagedFileSize: 1000
            )
        ) { error in
            XCTAssertEqual(error as? DownloadIntegrityFailure, .contentLengthMismatch)
        }
    }

    func test_acceptsResumedDownloadWhenServerOmitsCompleteSize() throws {
        try DownloadIntegrityValidator.validate(
            response: response(status: 206, contentLength: 400),
            stagedFileSize: 1000
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

    // MARK: - Pre-fork download-quality setting

    /// Pre-fork Plinx offered nine download qualities. Each maps to the closest preset that never
    /// exceeds the bitrate or the height the parent chose.
    func test_legacyDownloadQualitiesMapToPresetsThatNeverExceedTheChosenCaps() throws {
        let legacyCaps: [String: (videoBitrateKbps: Int, height: Int)] = [
            "megabits20_1080p": (20000, 1080),
            "megabits12_1080p": (12000, 1080),
            "megabits10_720p": (10000, 720),
            "megabits4_720p": (4000, 720),
            "megabits3_720p": (3000, 720),
            "megabits2_720p": (2000, 720),
            "kilobits1500_480p": (1500, 480),
            "kilobits720_328p": (720, 360),
        ]
        let expectedPresets: [String: TranscodeQualityPreset] = [
            "original": .original,
            "megabits20_1080p": .p1080_12mbps,
            "megabits12_1080p": .p1080_12mbps,
            "megabits10_720p": .p720_4mbps,
            "megabits4_720p": .p720_4mbps,
            "megabits3_720p": .p720_2mbps,
            "megabits2_720p": .p720_2mbps,
            "kilobits1500_480p": .p480_1_5mbps,
            "kilobits720_328p": .p360_700,
        ]
        XCTAssertEqual(Set(expectedPresets.keys), Set(legacyCaps.keys).union(["original"]))
        XCTAssertEqual(expectedPresets.count, 9)

        for (rawValue, expected) in expectedPresets {
            XCTAssertEqual(DownloadSettings.qualityPreset(legacyPlinxQuality: rawValue), expected, rawValue)
        }

        for (rawValue, caps) in legacyCaps {
            let preset = try XCTUnwrap(DownloadSettings.qualityPreset(legacyPlinxQuality: rawValue), rawValue)
            XCTAssertFalse(preset.isOriginal, rawValue)
            let bitrate = try XCTUnwrap(preset.maximumVideoBitrateKbps, rawValue)
            let height = try XCTUnwrap(preset.maximumHeight, rawValue)
            XCTAssertLessThanOrEqual(bitrate, caps.videoBitrateKbps, rawValue)
            XCTAssertLessThanOrEqual(height, caps.height, rawValue)
        }

        XCTAssertNil(DownloadSettings.qualityPreset(legacyPlinxQuality: "megabits40_4k"))
        XCTAssertNil(DownloadSettings.qualityPreset(legacyPlinxQuality: ""))
    }

    func test_downloadSettingsKeepThePreForkQualityChoice() throws {
        let legacy = try decodeDownloadSettings(#"{"wifiOnly":false,"quality":"megabits3_720p"}"#)
        XCTAssertEqual(legacy.qualityPreset, .p720_2mbps)
        XCTAssertFalse(legacy.wifiOnly)

        let original = try decodeDownloadSettings(#"{"quality":"original"}"#)
        XCTAssertEqual(original.qualityPreset, .original)

        let unknown = try decodeDownloadSettings(#"{"quality":"megabits40_4k"}"#)
        XCTAssertEqual(unknown.qualityPreset, .original)

        let empty = try decodeDownloadSettings("{}")
        XCTAssertEqual(empty, DownloadSettings())
    }

    func test_downloadSettingsPreferTheCurrentPresetOverThePreForkQuality() throws {
        let settings = try decodeDownloadSettings(
            #"{"qualityPreset":"p480_1_5mbps","quality":"megabits20_1080p"}"#
        )
        XCTAssertEqual(settings.qualityPreset, .p480_1_5mbps)

        var chosen = DownloadSettings()
        chosen.qualityPreset = .p360_700
        let roundTripped = try JSONDecoder().decode(DownloadSettings.self, from: JSONEncoder().encode(chosen))
        XCTAssertEqual(roundTripped, chosen)
    }

    // MARK: - Space-savings rule

    func test_spaceSavingsPolicyKeepsReducedQualityWhenVideoEstimateIsSmaller() {
        XCTAssertEqual(
            DownloadSpaceSavingsPolicy.estimatedOutputBytes(quality: .p720_2mbps, duration: 600),
            167_688_000
        )
        XCTAssertTrue(
            DownloadSpaceSavingsPolicy.shouldTranscode(
                quality: .p720_2mbps,
                sourceFileSize: 1_000_000_000,
                duration: 600
            )
        )
    }

    func test_spaceSavingsPolicyUsesOriginalWhenVideoEstimateCannotSaveSpace() {
        XCTAssertEqual(
            DownloadSpaceSavingsPolicy.estimatedOutputBytes(quality: .p720_2mbps, duration: 5400),
            1_509_192_000
        )
        XCTAssertFalse(
            DownloadSpaceSavingsPolicy.shouldTranscode(
                quality: .p720_2mbps,
                sourceFileSize: 1_000_000_000,
                duration: 5400
            )
        )
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
        XCTAssertFalse(
            DownloadSpaceSavingsPolicy.hasMinimumSavings(candidateSize: 1, sourceFileSize: 0)
        )
        XCTAssertFalse(
            DownloadSpaceSavingsPolicy.hasMinimumSavings(candidateSize: -1, sourceFileSize: 1_000_000_000)
        )
    }

    func test_spaceSavingsPolicyDownloadsOriginalWhenEstimatedSavingsAreTooSmall() {
        let sourceFileSize: Int64 = 500_000_000
        let estimate = DownloadSpaceSavingsPolicy.estimatedOutputBytes(quality: .p720_4mbps, duration: 900)

        // Smaller than the source, but by less than 20 percent.
        XCTAssertEqual(estimate, 481_032_000)
        XCTAssertLessThan(estimate ?? .max, sourceFileSize)
        XCTAssertFalse(
            DownloadSpaceSavingsPolicy.shouldTranscode(
                quality: .p720_4mbps,
                sourceFileSize: sourceFileSize,
                duration: 900
            )
        )
    }

    func test_spaceSavingsPolicyNeverTranscodesOriginal() {
        XCTAssertNil(DownloadSpaceSavingsPolicy.estimatedOutputBytes(quality: .original, duration: 600))
        XCTAssertFalse(
            DownloadSpaceSavingsPolicy.shouldTranscode(
                quality: .original,
                sourceFileSize: 1_000_000_000,
                duration: 600
            )
        )
    }

    /// Without a source size or a duration the savings cannot be estimated, so the requested
    /// preset's caps still apply (for example a 4K source on a phone).
    func test_spaceSavingsPolicyKeepsRequestedTranscodeWhenSizeOrDurationIsUnknown() {
        XCTAssertNil(DownloadSpaceSavingsPolicy.estimatedOutputBytes(quality: .p720_2mbps, duration: nil))
        XCTAssertNil(DownloadSpaceSavingsPolicy.estimatedOutputBytes(quality: .p720_2mbps, duration: 0))

        XCTAssertTrue(
            DownloadSpaceSavingsPolicy.shouldTranscode(quality: .p720_2mbps, sourceFileSize: nil, duration: 600)
        )
        XCTAssertTrue(
            DownloadSpaceSavingsPolicy.shouldTranscode(quality: .p720_2mbps, sourceFileSize: 0, duration: 600)
        )
        XCTAssertTrue(
            DownloadSpaceSavingsPolicy.shouldTranscode(
                quality: .p720_2mbps,
                sourceFileSize: 1_000_000_000,
                duration: nil
            )
        )
    }

    // MARK: - Source size

    func test_plexPartDecodesSourceFileSize() throws {
        let payload = Data(
            #"{"id":1,"key":"/library/parts/1/file.mkv","size":987654321}"#.utf8
        )

        let part = try JSONDecoder().decode(PlexPart.self, from: payload)
        XCTAssertEqual(part.size, 987_654_321)
    }

    // MARK: - Pre-fork download index entries

    func test_completedPreForkIndexEntryDecodesAndStaysPlayable() throws {
        let item = try decodePreForkItem(
            status: "completed",
            remoteReference: #"{"queueID":2,"itemID":1}"#
        )

        XCTAssertEqual(item.id, "legacy")
        XCTAssertEqual(item.status, .completed)
        XCTAssertTrue(item.isPlayable)
        XCTAssertNil(item.errorMessage)
        // The pre-fork Plex queue reference cannot be resumed and is dropped.
        XCTAssertNil(item.remoteReference)
        // Ownership comes only from the legacy migration (`accessScope`), never from the entry itself.
        XCTAssertNil(item.ownerID)
        XCTAssertEqual(item.itemID, "123")
        XCTAssertNil(item.identity)
        XCTAssertEqual(item.metadata.type, .movie)
        XCTAssertEqual(item.metadata.contentRating, "G")
        XCTAssertEqual(item.metadata.videoFileName, "video.mp4")
        XCTAssertEqual(item.metadata.requestedQuality, .original)
        XCTAssertEqual(item.metadata.effectiveQuality, .original)
    }

    func test_preForkTransferStillBeingPreparedBecomesFailedAndRetryable() throws {
        for status in ["deciding", "preparing"] {
            let item = try decodePreForkItem(status: status, taskIdentifier: 7)

            XCTAssertEqual(item.status, .failed, status)
            XCTAssertNil(item.taskIdentifier, status)
            XCTAssertEqual(item.errorMessage, String(localized: "downloads.status.interrupted"), status)
            XCTAssertFalse(item.isPlayable, status)
            XCTAssertTrue(item.canRetry(among: [item]), status)
        }
    }

    func test_preForkTransferWithUnresumableQueueReferenceBecomesFailed() throws {
        for status in ["queued", "downloading"] {
            let item = try decodePreForkItem(
                status: status,
                taskIdentifier: 7,
                remoteReference: #"{"queueID":2,"itemID":1}"#
            )

            XCTAssertEqual(item.status, .failed, status)
            XCTAssertNil(item.taskIdentifier, status)
            XCTAssertNil(item.remoteReference, status)
            XCTAssertFalse(item.isPlayable, status)
        }
    }

    func test_preForkDirectTransferKeepsItsStateForResume() throws {
        let item = try decodePreForkItem(status: "downloading", taskIdentifier: 7)

        XCTAssertEqual(item.status, .downloading)
        XCTAssertEqual(item.taskIdentifier, 7)
        XCTAssertNil(item.errorMessage)
        XCTAssertFalse(item.isPlayable)
    }

    func test_unknownPreForkStatusFailsClosed() throws {
        let item = try decodePreForkItem(status: "paused")

        XCTAssertEqual(item.status, .failed)
        XCTAssertFalse(item.isPlayable)
    }

    // MARK: - Helpers

    private func decodeDownloadSettings(_ json: String) throws -> DownloadSettings {
        try JSONDecoder().decode(DownloadSettings.self, from: Data(json.utf8))
    }

    /// A download as pre-fork Plinx wrote it to `index.json`: the metadata names the item by
    /// `ratingKey` with no server identity, and the entry carries the pre-fork quality, queue and
    /// enrollment fields this version no longer reads from the item itself.
    private func decodePreForkItem(
        status: String,
        taskIdentifier: Int? = nil,
        remoteReference: String? = nil
    ) throws -> DownloadItem {
        let taskIdentifierJSON = taskIdentifier.map(String.init) ?? "null"
        let remoteReferenceJSON = remoteReference.map { #","remoteReference":\#($0)"# } ?? ""
        let json = """
        {
          "id": "legacy",
          "status": "\(status)",
          "progress": 0.5,
          "bytesWritten": 50,
          "totalBytes": 100,
          "taskIdentifier": \(taskIdentifierJSON),
          "errorMessage": null,
          "preparationProgress": 0.25,
          "requestedQuality": "megabits3_720p",
          "effectiveQuality": "megabits3_720p",
          "sourceFileSize": 1000000000,
          "estimatedOutputBytes": 244188000,
          "qualityResolutionReason": "requested",
          "deliveryDecision": "transcode",
          "accessScope": {"serverIdentifier": "server-a", "accessScopeIdentifier": "profile-a"},
          "metadata": {
            "ratingKey": "123",
            "guid": "plex://movie/123",
            "type": "movie",
            "title": "Legacy",
            "genres": [],
            "year": 2024,
            "duration": 100,
            "contentRating": "G",
            "videoFileName": "video.mp4",
            "createdAt": 1
          }\(remoteReferenceJSON)
        }
        """
        return try JSONDecoder().decode(DownloadItem.self, from: Data(json.utf8))
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
