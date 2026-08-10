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
}
