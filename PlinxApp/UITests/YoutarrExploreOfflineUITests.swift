import XCTest

final class YoutarrExploreOfflineUITests: XCTestCase {
    func test_selectingExploreLoadsAndRendersFixtureVideoWithoutServer() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--disable-animations"]
        app.launchEnvironment["PLINX_UI_TEST_SCREEN"] = "youtarrExploreOffline"
        app.launch()

        let exploreTab = app.buttons["main.tab.explore.fixture"]
        XCTAssertTrue(
            exploreTab.waitForExistence(timeout: 10),
            "Expected the offline Explore tab fixture."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["youtarr.explore.video.fixture0001"].exists,
            "Explore content must remain unmounted before the tab is selected."
        )

        exploreTab.tap()

        XCTAssertTrue(
            app.otherElements["youtarr.explore.screen"].waitForExistence(timeout: 10),
            "Selecting Explore should mount its production screen."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["youtarr.explore.video.fixture0001"]
                .waitForExistence(timeout: 10),
            "Selecting Explore should decode, safety-filter, and render the fixture video."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["youtarr.explore.video.fixturesh01"].exists,
            "The cross-channel feed should include an allowed short."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["youtarr.explore.video.fixturelv01"].exists,
            "The cross-channel feed should include an allowed livestream."
        )

        app.otherElements["youtarr.explore.screen"].swipeDown()
        XCTAssertTrue(
            app.descendants(matching: .any)["youtarr.explore.video.fixture0001"]
                .waitForExistence(timeout: 10),
            "Refreshing must preserve the committed catalog."
        )
        XCTAssertFalse(
            app.staticTexts["Explore Couldn’t Load"].exists,
            "A successful or cancelled refresh must not show a network failure."
        )

        app.buttons["main.tab.home.fixture"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["youtarr.explore.video.fixture0001"]
                .waitForNonExistence(timeout: 10),
            "Leaving Explore should tear down its catalog content."
        )

        exploreTab.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["youtarr.explore.video.fixture0001"]
                .waitForExistence(timeout: 10),
            "Returning to Explore should reliably reload and render the catalog."
        )
    }

    func test_genuineInitialFailureShowsGlassRetryAction() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--disable-animations"]
        app.launchEnvironment["PLINX_UI_TEST_SCREEN"] = "youtarrExploreOffline"
        app.launchEnvironment["PLINX_YOUTARR_FIXTURE_FAILURE"] = "1"
        app.launch()

        app.buttons["main.tab.explore.fixture"].tap()

        XCTAssertTrue(
            app.staticTexts["Explore Couldn’t Load"].waitForExistence(timeout: 10)
        )
        let retry = app.buttons["youtarr.explore.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertEqual(retry.label, "Try Again")
    }
}
