import XCTest

/// Deterministic capture checks for the real Plinx surfaces used by the
/// cross-platform visual audit. These routes are available only when the app
/// is launched with `--ui-testing`.
final class VisualAuditUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--disable-animations"]
    }

    func test_captureSignIn() {
        launch(screen: "signIn")
        XCTAssertTrue(app.staticTexts["Grown-up step"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["Connect your Plex library"].exists)
        XCTAssertTrue(app.buttons["signIn.primaryButton"].waitForExistence(timeout: 12))
        attachScreenshot(name: "sign-in")
    }

    func test_signInPrimaryActionRemainsReachableAfterScrolling() {
        launch(screen: "signIn")
        let primaryButton = app.buttons["signIn.primaryButton"]
        XCTAssertTrue(primaryButton.waitForExistence(timeout: 12))

        if !primaryButton.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }

        XCTAssertTrue(primaryButton.isHittable)
    }

    func test_captureParentalGate() {
        launch(screen: "parentalGate")
        XCTAssertTrue(app.staticTexts["parentalGate.title"].waitForExistence(timeout: 12))
        attachScreenshot(name: "parental-gate")
    }

    func test_captureSettings() {
        launch(screen: "settings")
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 12))
        attachScreenshot(name: "settings")
    }

    func test_captureProfileSwitcher() {
        launch(screen: "profileSwitcher")
        XCTAssertTrue(
            waitForAny(
                [
                    app.staticTexts["Select Profile"],
                    app.staticTexts["Who's watching?"],
                    app.staticTexts["Choose a Profile"],
                    app.staticTexts["Profiles"],
                    app.staticTexts["Unable to load profiles. Please try again."],
                    app.progressIndicators.firstMatch,
                ],
                timeout: 15
            )
        )
        attachScreenshot(name: "profile-switcher")
    }

    func test_captureServerSelection() {
        launch(screen: "selectServer")
        XCTAssertTrue(
            waitForAny(
                [
                    app.staticTexts["Select your server"],
                    app.staticTexts["No servers found"],
                    app.staticTexts["Choose a Server"],
                    app.staticTexts["Select Server"],
                    app.progressIndicators.firstMatch,
                ],
                timeout: 15
            )
        )
        attachScreenshot(name: "server-selection")
    }

    func test_capturePlayerSettings() {
        launch(screen: "playerSettings")
        XCTAssertTrue(app.buttons["English"].waitForExistence(timeout: 12))
        attachScreenshot(name: "player-settings")
    }

    func test_captureDownloadsGrid() {
        app.launchEnvironment["PLINX_UI_TEST_SEED"] = "17"
        launch(screen: "downloadsGrid")
        XCTAssertTrue(app.otherElements["downloads.thumbnail.movie-0"].waitForExistence(timeout: 12))
        attachScreenshot(name: "downloads-grid")
    }

    func test_captureLoadingGallery() {
        launch(screen: "loadingGallery")
        XCTAssertTrue(
            app.descendants(matching: .any)["loading.indicator.compact"]
                .waitForExistence(timeout: 12)
        )
        XCTAssertTrue(app.descendants(matching: .any)["loading.indicator.hero"].exists)
        attachScreenshot(name: "loading-gallery")
    }

    func test_capturePlayerBuffering() {
        launch(screen: "playerBuffering")
        XCTAssertTrue(
            app.descendants(matching: .any)["player.buffering.plinx"]
                .waitForExistence(timeout: 12)
        )
        attachScreenshot(name: "player-buffering")
    }

    private func launch(screen: String) {
        app.launchEnvironment["PLINX_UI_TEST_SCREEN"] = screen
        app.launch()
    }

    private func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: \.exists) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }

    private func attachScreenshot(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
