import XCTest

final class LaunchSmokeUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func test_appLaunches() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--disable-animations"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should launch into foreground")
    }

    func test_demoModeRendersProductionHomeAndSyntheticPlayback() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--disable-animations"]
        app.launch()

        let demoButton = app.buttons["signIn.demoButton"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 15), "The credential-free demo entry point should be visible")
        demoButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["home.hub.moviesAndTV"].waitForExistence(timeout: 20),
            "Demo mode should render the production Home view from synthetic fixtures",
        )

        let firstCard = app.otherElements["home.card.moviesAndTV.0"].firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 10), "Demo Home should expose a playable fixture card")
        firstCard.tap()

        XCTAssertTrue(
            app.otherElements["media.detail.screen"].waitForExistence(timeout: 20),
            "Demo fixture metadata should open the production detail screen",
        )

        let playButton = app.buttons["media.detail.play"].firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 20), "Demo detail should expose the production play action")
        playButton.tap()

        XCTAssertTrue(
            app.buttons["demo.player.close"].waitForExistence(timeout: 20),
            "Demo playback should use the explicit synthetic playback surface",
        )
    }
}
