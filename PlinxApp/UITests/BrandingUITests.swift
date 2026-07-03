import XCTest

final class BrandingUITests: XCTestCase {

    func test_parentalGate_showsBrandLogoAndAccentSemanticTitle() {
        let app = launch(screen: "parentalGate")

        let logo = app.images["parentalGate.logo"]
        XCTAssertTrue(logo.waitForExistence(timeout: 8), "Parental gate should render branded logo")
        XCTAssertEqual(logo.value as? String, "LogoFullColor")

        let title = app.staticTexts["parentalGate.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8), "Parental gate title should be visible")
        XCTAssertEqual(title.value as? String, "darkOnGreenGradient", "Parental gate title should use dark-on-green-gradient semantic hook")

        XCTAssertEqual(app.activityIndicators.count, 0, "Parental gate should not show a loading spinner")
        XCTAssertFalse(app.staticTexts["Settings"].exists, "Parental gate popup should not show settings title text")
    }

    func test_signIn_showsFullColorLogoAndLiquidGlassPrimaryButton() {
        let app = launch(screen: "signIn")

        let logo = app.images["signIn.logo.fullColor"]
        XCTAssertTrue(logo.waitForExistence(timeout: 8), "Sign-in should render full-color logo")
        XCTAssertEqual(logo.value as? String, "LogoFullColor", "Sign-in logo should resolve to full-color asset")

        let primaryButton = app.buttons["signIn.primaryButton"]
        XCTAssertTrue(primaryButton.waitForExistence(timeout: 8), "Sign-in primary button should be present")
        XCTAssertEqual(primaryButton.value as? String, "liquidGlassPrimary", "Primary button should expose liquid-glass semantic hook")
    }

    func test_playerSettings_usesBrandedSelectionRows_withoutPlaybackSpeed() {
        let app = launch(screen: "playerSettings")

        let englishRow = app.buttons["English"]
        XCTAssertTrue(englishRow.waitForExistence(timeout: 8), "Expected branded audio row to render")
        XCTAssertEqual(englishRow.value as? String, "selected", "Selected track row should expose selected state")

        let spanishRow = app.buttons["Spanish"]
        XCTAssertTrue(spanishRow.waitForExistence(timeout: 8), "Expected secondary audio row to render")
        XCTAssertEqual(spanishRow.value as? String, "not selected", "Unselected track row should expose not selected state")

        XCTAssertFalse(app.buttons["Speed"].exists, "Playback speed should not appear in the player settings UI")
        XCTAssertFalse(app.staticTexts["Speed"].exists, "Playback speed label should not appear in the player settings UI")
    }

    private func launch(screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--disable-animations"]
        app.launchEnvironment["PLINX_UI_TEST_SCREEN"] = screen
        app.launch()
        return app
    }
}
