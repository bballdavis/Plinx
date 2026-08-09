import XCTest

final class BrandingUITests: XCTestCase {

    func test_parentalGate_showsBrandLogoAndAccentSemanticTitle() {
        let app = launch(screen: "parentalGate")

        let logo = app.images["parentalGate.logo"]
        XCTAssertTrue(logo.waitForExistence(timeout: 8), "Parental gate should render branded logo")
        XCTAssertEqual(logo.value as? String, "BrandLockupStackedOnGradient")

        let title = app.staticTexts["parentalGate.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8), "Parental gate title should be visible")
        XCTAssertEqual(title.value as? String, "darkOnBrandGradient", "Parental gate title should use dark text on the bright brand gradient")

        let unlockButton = app.buttons["parentalGate.unlock"]
        XCTAssertTrue(unlockButton.waitForExistence(timeout: 8), "Parental gate should expose the green Unlock action")
        XCTAssertEqual(unlockButton.value as? String, "greenBrandPrimary")

        XCTAssertEqual(app.activityIndicators.count, 0, "Parental gate should not show a loading spinner")
        XCTAssertFalse(app.staticTexts["Settings"].exists, "Parental gate popup should not show settings title text")
    }

    func test_homeLoading_usesOneLargeAnimatedIdentity_withoutLoadingCopy() {
        let app = launch(screen: "homeLoading")

        let loadingIdentity = app.descendants(matching: .any)["plinx.loading.branded"]
        XCTAssertTrue(
            loadingIdentity.waitForExistence(timeout: 8),
            "Home loading should expose the hero Plinx identity"
        )
        XCTAssertEqual(
            loadingIdentity.value as? String,
            "heroAnimatedBeaconWithWordmark"
        )
        XCTAssertFalse(app.staticTexts["Loading home"].exists)
        XCTAssertFalse(app.staticTexts["Loading your shows…"].exists)
        XCTAssertEqual(app.activityIndicators.count, 0)
    }

    func test_appTransitionLoading_keepsHydrationAndHomeIdentityInTheSameFrame() {
        let hydrationApp = launch(screen: "appHydrating")
        let hydrationIdentity = hydrationApp.descendants(matching: .any)["plinx.loading.branded"]
        XCTAssertTrue(hydrationIdentity.waitForExistence(timeout: 8))
        let hydrationFrame = hydrationIdentity.frame
        hydrationApp.terminate()

        let homeApp = launch(screen: "homeLoading")
        let homeIdentity = homeApp.descendants(matching: .any)["plinx.loading.branded"]
        XCTAssertTrue(homeIdentity.waitForExistence(timeout: 8))
        let homeFrame = homeIdentity.frame

        XCTAssertEqual(hydrationFrame.midX, homeFrame.midX, accuracy: 1)
        XCTAssertEqual(hydrationFrame.midY, homeFrame.midY, accuracy: 1)
        XCTAssertEqual(hydrationFrame.width, homeFrame.width, accuracy: 1)
        XCTAssertEqual(hydrationFrame.height, homeFrame.height, accuracy: 1)
    }

    func test_contentLoading_usesRegularIndicator_withoutRepeatedLogo() {
        let app = launch(screen: "contentLoading")

        XCTAssertTrue(
            app.descendants(matching: .any)["plinx.loading.content"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertFalse(app.descendants(matching: .any)["plinx.loading.branded"].exists)
        XCTAssertEqual(app.activityIndicators.count, 0)
    }

    func test_homeHeader_logoFillsExistingChromeRow_withoutMovingContentDown() {
        let app = launch(screen: "homeHeader")

        let logo = app.images["home.header.logo"]
        let search = app.buttons["home.header.search"]
        let firstSection = app.staticTexts["home.header.preview.firstSection"]

        XCTAssertTrue(logo.waitForExistence(timeout: 8))
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        XCTAssertTrue(firstSection.waitForExistence(timeout: 8))
        XCTAssertEqual(logo.frame.height, search.frame.height, accuracy: 1)
        XCTAssertLessThanOrEqual(logo.frame.maxY, search.frame.maxY + 1)
        XCTAssertGreaterThan(firstSection.frame.minY, search.frame.maxY)
    }

    func test_signIn_showsContrastSafeLogoAndLiquidGlassPrimaryButton() {
        let app = launch(screen: "signIn")

        let logo = app.images["signIn.logo.fullColor"]
        XCTAssertTrue(logo.waitForExistence(timeout: 8), "Sign-in should render contrast-safe branding")
        XCTAssertEqual(logo.value as? String, "BrandLockupWhite", "Compact sign-in should use the white lockup over the colored portal")

        let title = app.staticTexts["signIn.portal.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(
            logo.frame.height,
            title.frame.height,
            "The Plinx identity should visually lead the sign-in headline"
        )

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

    func test_loadingGallery_usesCompactAndBrandedLoadingTiers_withoutNativeSpinner() {
        let app = launch(screen: "loadingGallery")

        XCTAssertTrue(
            app.descendants(matching: .any)["loading.indicator.compact"]
                .waitForExistence(timeout: 8),
            "Inline loading should expose the compact logo-free Plinx indicator"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["loading.indicator.regular"]
                .waitForExistence(timeout: 8),
            "Larger app loading should expose the regular Plinx indicator with its restrained mark"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["loading.indicator.hero"]
                .waitForExistence(timeout: 8),
            "Video loading should expose the hero Plinx indicator"
        )
        XCTAssertEqual(
            app.activityIndicators.count,
            0,
            "The gallery should not contain a native activity indicator"
        )
    }

    func test_playerBuffering_usesExactlyOnePlinxOverlay_withoutNativeSpinner() {
        let app = launch(screen: "playerBuffering")
        let overlays = app.descendants(matching: .any)
            .matching(identifier: "player.buffering.plinx")

        XCTAssertTrue(
            overlays.firstMatch.waitForExistence(timeout: 8),
            "Player buffering should render the Plinx-owned overlay"
        )
        XCTAssertEqual(overlays.count, 1, "Player buffering should render one branded loader")
        XCTAssertEqual(
            app.activityIndicators.count,
            0,
            "Player buffering should not render the native activity indicator"
        )
    }

    func test_playerLoading_usesHeroIndicatorAndLargeBackButton() {
        let app = launch(screen: "playerLoading")

        let loader = app.descendants(matching: .any)["player.loading.plinx"]
        XCTAssertTrue(loader.waitForExistence(timeout: 8))

        let backButton = app.buttons["player.back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(backButton.frame.width, 66)
        XCTAssertEqual(app.activityIndicators.count, 0)
    }

    private func launch(screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--disable-animations"]
        app.launchEnvironment["PLINX_UI_TEST_SCREEN"] = screen
        app.launch()
        return app
    }
}
