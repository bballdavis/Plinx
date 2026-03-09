import XCTest

final class DownloadThumbnailLayoutUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["--ui-testing", "--disable-animations"]
        app.launchEnvironment["PLINX_UI_TEST_SCREEN"] = "downloadsGrid"
        app.launchEnvironment["PLINX_UI_TEST_SEED"] = "17"
        app.launch()
    }

    func test_downloadGridRendersPortraitAndLandscapeTypesCorrectly() throws {
        let movieThumb = app.otherElements["downloads.thumbnail.movie-0"]
        let tvThumb = app.otherElements["downloads.thumbnail.tv-1"]
        let clipThumb = app.otherElements["downloads.thumbnail.clip-2"]

        XCTAssertTrue(movieThumb.waitForExistence(timeout: 8))
        XCTAssertTrue(tvThumb.waitForExistence(timeout: 8))
        XCTAssertTrue(clipThumb.waitForExistence(timeout: 8))

        XCTAssertGreaterThan(movieThumb.frame.height, movieThumb.frame.width,
                             "Movie downloads should render as portrait cards")
        XCTAssertGreaterThan(tvThumb.frame.height, tvThumb.frame.width,
                             "TV downloads should render as portrait cards")
        XCTAssertGreaterThan(clipThumb.frame.width, clipThumb.frame.height,
                             "Other-video downloads should render as landscape cards even with bad cached poster art")
    }

    func test_downloadGridShowsTwoRenderedRowsAndProgressWithinClipCard() throws {
        let thumbnails = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "downloads.thumbnail.")
        )
        XCTAssertGreaterThanOrEqual(thumbnails.count, 8)

        var distinctRows: [CGFloat] = []
        for index in 0..<min(thumbnails.count, 8) {
            let frame = thumbnails.element(boundBy: index).frame
            guard frame.width > 0, frame.height > 0 else { continue }
            if distinctRows.allSatisfy({ abs($0 - frame.minY) > 20 }) {
                distinctRows.append(frame.minY)
            }
        }
        XCTAssertGreaterThanOrEqual(distinctRows.count, 2, "Fixture set should fill at least two visible rows")

        let clipThumb = app.otherElements["downloads.thumbnail.clip-2"]
        let clipProgress = app.descendants(matching: .any)["downloads.progress.clip-2"]
        XCTAssertTrue(clipProgress.waitForExistence(timeout: 8))

        XCTAssertLessThanOrEqual(clipProgress.frame.width, clipThumb.frame.width,
                                 "Download progress bar should stay within the clip thumbnail width")
        XCTAssertGreaterThan(clipProgress.frame.width, clipThumb.frame.width * 0.4,
                             "Download progress bar should span a meaningful width inside the clip card")
    }
}