import XCTest

final class SeasonDownloadOfflineUITests: XCTestCase {
    func test_seasonPickerListsOnlyCurrentSeasonAndSupportsSelectAll() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--disable-animations"]
        app.launchEnvironment["PLINX_UI_TEST_SCREEN"] = "seasonDownloadOffline"
        app.launch()

        let moreInfo = app.buttons["season.fixture.moreInfo"]
        XCTAssertTrue(moreInfo.waitForExistence(timeout: 10))
        moreInfo.tap()
        XCTAssertTrue(app.descendants(matching: .any)["media.detail.screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Season 1"].exists)

        let download = app.buttons["media.detail.download"]
        XCTAssertTrue(download.waitForExistence(timeout: 10))
        download.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["downloads.episodeSelection"].waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.staticTexts["Season 1"].exists)
        XCTAssertFalse(app.staticTexts["No seasons available."].exists)
        XCTAssertTrue(app.buttons["downloads.episodeSelection.episode.episode-1"].exists)
        XCTAssertTrue(app.buttons["downloads.episodeSelection.episode.episode-1"].isEnabled)
        XCTAssertTrue(app.buttons["downloads.episodeSelection.episode.episode-2"].isEnabled)

        app.buttons["downloads.episodeSelection.selectAll"].tap()

        let submit = app.buttons["downloads.episodeSelection.submit"]
        XCTAssertTrue(submit.exists)
        XCTAssertEqual(submit.label, "Download (3)")
    }
}
