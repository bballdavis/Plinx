import XCTest
@testable import Plinx

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

    func test_legacyDownloadQualityFallsBackToOriginal() throws {
        let legacy = Data(#""megabits20_1080p""#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(DownloadQuality.self, from: legacy), .original)
        XCTAssertEqual(DownloadQuality.allCases, [.original])
    }

    private func response(status: Int, contentLength: Int64? = nil) -> HTTPURLResponse {
        let headers = contentLength.map { ["Content-Length": String($0)] }
        return HTTPURLResponse(
            url: URL(string: "https://example.test/video")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }
}
