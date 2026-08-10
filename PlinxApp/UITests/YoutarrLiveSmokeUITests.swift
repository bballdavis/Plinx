import XCTest

/// Opt-in end-to-end coverage for a real parent-controlled Youtarr instance.
///
/// These tests skip in normal CI and local test runs. Set PLINX_YOUTARR_LIVE=1,
/// PLINX_YOUTARR_URL, and PLINX_YOUTARR_API_KEY in the xcodebuild environment.
final class YoutarrLiveSmokeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let environment = ProcessInfo.processInfo.environment
        guard environment["PLINX_YOUTARR_LIVE"] == "1",
              environment["PLINX_YOUTARR_URL"]?.isEmpty == false,
              environment["PLINX_YOUTARR_API_KEY"]?.isEmpty == false else {
            throw XCTSkip("Live Youtarr smoke tests are opt-in.")
        }

        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--disable-animations"]
        for key in [
            "PLINX_YOUTARR_LIVE",
            "PLINX_YOUTARR_URL",
            "PLINX_YOUTARR_API_KEY",
            "PLINX_YOUTARR_MAX_TV_RATING",
        ] {
            if let value = environment[key] {
                app.launchEnvironment[key] = value
            }
        }
    }

    func test_liveExploreLoadsLandscapeVideoAndRequestsPage() {
        app.launchEnvironment["PLINX_UI_TEST_SCREEN"] = "youtarrExploreLive"
        app.launch()

        let video = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "youtarr.explore.video."))
            .firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 30), "Expected a requestable live video.")
        attachScreenshot(name: "youtarr-explore-live")

        let requests = app.buttons["My Requests"]
        XCTAssertTrue(requests.waitForExistence(timeout: 10))
        requests.tap()
        XCTAssertTrue(app.otherElements["youtarr.requests.screen"].waitForExistence(timeout: 20))
        attachScreenshot(name: "youtarr-requests-live")
    }

    /// Exercises the real configured RootTabView instead of the isolated live
    /// fixture. This is intentionally a second opt-in because it requires an
    /// existing live Plex session in the selected simulator. The Youtarr
    /// configuration itself is injected only for this process.
    func test_liveExploreLoadsThroughConfiguredMainTab() throws {
        guard ProcessInfo.processInfo.environment["PLINX_YOUTARR_LIVE_MAIN_TAB"] == "1" else {
            throw XCTSkip("Configured main-tab smoke test is separately opt-in.")
        }

        app.launch()

        let exploreTab = app.buttons["main.tab.explore"]
        XCTAssertTrue(
            exploreTab.waitForExistence(timeout: 30),
            "Expected Explore in the configured main tab bar."
        )
        exploreTab.tap()

        XCTAssertTrue(
            app.otherElements["youtarr.explore.screen"].waitForExistence(timeout: 10),
            "Expected the full Explore tab."
        )
        let video = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "youtarr.explore.video."))
            .firstMatch
        XCTAssertTrue(
            video.waitForExistence(timeout: 30),
            "Expected a requestable live video through the normal tab flow."
        )
        attachScreenshot(name: "youtarr-explore-main-tab-live")

        video.tap()
        XCTAssertTrue(
            app.otherElements["youtarr.details.screen"].waitForExistence(timeout: 10),
            "Expected tapping a video to present its detail modal."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(
                    NSPredicate(
                        format: "identifier BEGINSWITH %@",
                        "youtarr.details.request."
                    )
                )
                .firstMatch
                .waitForExistence(timeout: 10),
            "Expected a modal-width request control."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["youtarr.details.loaded"]
                // A cold Youtarr detail lookup may populate its metadata cache
                // before returning; keep the release smoke above that bound.
                .waitForExistence(timeout: 90),
            "Expected the live video-detail endpoint to return rich metadata."
        )
        attachScreenshot(name: "youtarr-video-detail-main-tab-live")
    }

    private func attachScreenshot(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
