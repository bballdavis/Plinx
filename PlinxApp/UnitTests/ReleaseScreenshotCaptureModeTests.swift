import XCTest
@testable import Plinx

final class ReleaseScreenshotCaptureModeTests: XCTestCase {
    private let arguments = ["Plinx", "--ui-testing", "--release-screenshot-capture"]
    private let environment = [
        "PLINX_UI_TEST_MODE": "live",
        "PLINX_RELEASE_CAPTURE_DETAIL_RATING_KEY": "detail-1",
        "PLINX_RELEASE_CAPTURE_PLAYBACK_RATING_KEY": "playback-2",
        "PLINX_RELEASE_CAPTURE_SEARCH_QUERY": "approved family title",
    ]

    func test_captureModeRequiresAllExplicitLaunchGates() {
        XCTAssertTrue(
            ReleaseScreenshotCaptureMode.isActive(
                arguments: arguments,
                environment: environment
            )
        )
        XCTAssertFalse(
            ReleaseScreenshotCaptureMode.isActive(
                arguments: ["Plinx", "--ui-testing"],
                environment: environment
            )
        )
        XCTAssertFalse(
            ReleaseScreenshotCaptureMode.isActive(
                arguments: arguments,
                environment: [:]
            )
        )
    }

    func test_captureSelectorsFailClosedToExactApprovedItems() {
        XCTAssertTrue(
            ReleaseScreenshotCaptureMode.allowsDetail(
                ratingKey: "detail-1",
                arguments: arguments,
                environment: environment
            )
        )
        XCTAssertFalse(
            ReleaseScreenshotCaptureMode.allowsDetail(
                ratingKey: "playback-2",
                arguments: arguments,
                environment: environment
            )
        )
        XCTAssertTrue(
            ReleaseScreenshotCaptureMode.allowsPlayback(
                ratingKey: "playback-2",
                arguments: arguments,
                environment: environment
            )
        )
        XCTAssertFalse(
            ReleaseScreenshotCaptureMode.allowsPlayback(
                ratingKey: "detail-1",
                arguments: arguments,
                environment: environment
            )
        )
        XCTAssertEqual(
            ReleaseScreenshotCaptureMode.searchQuery(environment: environment),
            "approved family title"
        )
    }

    func test_captureModeBlocksEveryPlexWatchStateEndpoint() throws {
        for path in ["/:/timeline", "/:/scrobble", "/:/unscrobble"] {
            let url = try XCTUnwrap(URL(string: "https://plex.invalid\(path)"))
            XCTAssertTrue(
                ReleaseScreenshotCaptureMode.shouldBlockWatchMutation(
                    url: url,
                    arguments: arguments,
                    environment: environment
                )
            )
        }

        let metadataURL = try XCTUnwrap(URL(string: "https://plex.invalid/library/metadata/1"))
        XCTAssertFalse(
            ReleaseScreenshotCaptureMode.shouldBlockWatchMutation(
                url: metadataURL,
                arguments: arguments,
                environment: environment
            )
        )
    }

    func test_unresolvedSchemeMacrosAreNotCredentialsOrSelectors() {
        XCTAssertNil(
            LiveTestCredentials.value(
                named: "PLINX_PLEX_SERVER_URL",
                environment: ["PLINX_PLEX_SERVER_URL": "$(PLINX_PLEX_SERVER_URL)"]
            )
        )
        XCTAssertNil(
            ReleaseScreenshotCaptureMode.detailRatingKey(
                environment: [
                    "PLINX_RELEASE_CAPTURE_DETAIL_RATING_KEY":
                        "$(PLINX_RELEASE_CAPTURE_DETAIL_RATING_KEY)"
                ]
            )
        )
    }
}
