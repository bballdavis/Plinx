import XCTest
import UIKit

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

    func test_demoModeRendersProductionHomeAndRealPlayback() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--disable-animations"]
        app.launch()
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }

        let information = app.buttons["signIn.infoButton"]
        XCTAssertTrue(information.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["signIn.demoButton"].exists, "Demo access belongs in sign-in information")
        let signIn = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        signIn.name = "refreshed-sign-in"
        signIn.lifetime = .keepAlways
        add(signIn)

        information.tap()
        let demoButton = app.buttons["signIn.demoButton"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 10), "The information sheet must explain and expose demo access")
        XCTAssertTrue(app.staticTexts["Connect your Plex account"].exists)
        let help = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        help.name = "sign-in-information"
        help.lifetime = .keepAlways
        add(help)
        app.buttons["signIn.infoDone"].tap()
        XCTAssertTrue(app.buttons["signIn.primaryButton"].isHittable)
        XCTAssertFalse(demoButton.exists, "Dismissing help must not start demo mode")
        information.tap()
        XCTAssertTrue(demoButton.waitForExistence(timeout: 10))
        demoButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["home.hub.moviesAndTV"].waitForExistence(timeout: 20),
            "Demo mode should render the production Home view from synthetic fixtures",
        )

        let home = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        home.name = "demo-browse-navigation"
        home.lifetime = .keepAlways
        add(home)
        let navigation = app.descendants(matching: .any)["main.navigation.surface"].firstMatch
        XCTAssertTrue(navigation.exists)
        XCTAssertEqual(navigation.frame.midX, app.frame.midX, accuracy: 3,
                       "Floating navigation should center on the full display, including any side status region")

        // The card's artwork and title share the container identifier. The
        // title is the stable hittable accessibility target on both sizes.
        let firstCard = app.buttons.matching(identifier: "home.card.moviesAndTV.0")
            .matching(NSPredicate(format: "label == %@", "Moonbound")).firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 10), "Demo Home should expose a playable fixture card")
        firstCard.press(forDuration: 0.8)
        let details = app.buttons["quickAction.option.go-details"]
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        details.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["media.detail.screen"].firstMatch.waitForExistence(timeout: 20),
            "Demo fixture metadata should open the production detail screen",
        )

        let playButton = app.buttons["media.detail.play"].firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 20), "Demo detail should expose the production play action")
        let detail = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        detail.name = "demo-media-detail"
        detail.lifetime = .keepAlways
        add(detail)
        playButton.tap()

        let playPause = app.buttons["player.playPause"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 20), "Demo must use the production player")
        // Interact as soon as controls appear: extra accessibility waits can
        // consume the three-second auto-hide interval on a larger simulator.
        let originalLabel = playPause.label
        playPause.tap()
        let changed = NSPredicate(format: "label != %@", originalLabel)
        expectation(for: changed, evaluatedWith: playPause)
        waitForExpectations(timeout: 5)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "demo-production-player"
        attachment.lifetime = .keepAlways
        add(attachment)
        let timeline = app.descendants(matching: .any)["player.timeline"].firstMatch
        XCTAssertTrue(timeline.exists)
        XCTAssertFalse(app.buttons["demo.player.close"].exists)
    }

    func test_playerFitFillSurvivesHiddenControls() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--disable-animations", "--app-store-landscape"]
        app.launchEnvironment["PLINX_UI_TEST_SCREEN"] = "demoPlayer"
        app.launch()
        let videoFit = app.buttons["player.videoFit"]
        XCTAssertTrue(videoFit.waitForExistence(timeout: 20))
        XCTAssertEqual(videoFit.value as? String, "Fit")
        videoFit.tap()
        XCTAssertEqual(videoFit.value as? String, "Fill")
        let filled = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        filled.name = "demo-player-fill"
        filled.lifetime = .keepAlways
        add(filled)

        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: videoFit)
        waitForExpectations(timeout: 10)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(videoFit.waitForExistence(timeout: 5))
        XCTAssertEqual(videoFit.value as? String, "Fill", "Auto-hiding controls must preserve the session choice")
        videoFit.tap()
        XCTAssertEqual(videoFit.value as? String, "Fit")
        let timeline = app.descendants(matching: .any)["player.timeline"].firstMatch
        XCTAssertEqual(timeline.frame.midX, app.frame.midX, accuracy: 3,
                       "The landscape timeline should span and center on the display rather than the side-status safe region")
        let fitted = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        fitted.name = "demo-player-fit"
        fitted.lifetime = .keepAlways
        add(fitted)
        app.buttons["gearshape"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5),
                      "Settings must remain tappable in the reclaimed side area")
        app.buttons["Done"].tap()
    }
}
