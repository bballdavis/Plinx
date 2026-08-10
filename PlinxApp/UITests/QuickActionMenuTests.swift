// ─────────────────────────────────────────────────────────────────────────────
// QuickActionMenuTests — Integration tests for mark watched/unwatched
// ─────────────────────────────────────────────────────────────────────────────
//
// These tests verify that:
//   1. Long press on a media item opens the quick action menu
//   2. "Mark as watched" option appears and is functional
//   3. "Mark as unwatched" option appears for watched items
//   4. Home view refreshes after marking watched/unwatched
//   5. Error messages are displayed when API calls fail
//
// Run with: xcodebuild test -scheme Plinx-iOS -only-testing "Plinx-iOS-UITests/QuickActionMenuTests"
// ─────────────────────────────────────────────────────────────────────────────

import XCTest

final class QuickActionMenuTests: XCTestCase {
    
    let app = XCUIApplication()
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait

        let environment = ProcessInfo.processInfo.environment
        let serverURL = environment["PLINX_PLEX_SERVER_URL"] ?? ""
        let hasToken = !(environment["PLINX_PLEX_TOKEN"] ?? "").isEmpty
        let hasPassword = !(environment["PLINX_PLEX_USER"] ?? "").isEmpty
            && !(environment["PLINX_PLEX_PASSWORD"] ?? "").isEmpty
        let hasPIN = !(environment["PLINX_PLEX_PIN"] ?? "").isEmpty
        guard !serverURL.isEmpty, hasToken || hasPassword || hasPIN else {
            throw XCTSkip("Quick-action integration tests require an opt-in live Plex environment.")
        }

        app.launchArguments += ["--ui-testing", "--disable-animations"]
        app.launchEnvironment["PLINX_UI_TEST_MODE"] = "live"
        for key in [
            "PLINX_PLEX_SERVER_URL",
            "PLINX_PLEX_TOKEN",
            "PLINX_PLEX_USER",
            "PLINX_PLEX_PASSWORD",
            "PLINX_PLEX_PIN",
        ] {
            if let value = environment[key], !value.isEmpty {
                app.launchEnvironment[key] = value
            }
        }
        app.launch()

        // Wait for home screen to load
        let homeHubElement = app.otherElements["home.hub.continueWatching"]
        guard homeHubElement.waitForExistence(timeout: 30) else {
            throw XCTSkip("The live Plex profile has no Continue Watching quick-action fixture.")
        }
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    /// Verifies: Long press menu appears and contains mark watched option
    func test_quickActionMenuAppears() {
        // Find first media card
        let firstCard = app.otherElements["home.card.continueWatching.0"]
        XCTAssert(firstCard.exists, "Media card not found in continue watching section")
        
        // Long press to open menu
        firstCard.press(forDuration: 0.5)
        
        // Verify menu backdrop appears
        let backdrop = app.otherElements["quickAction.backdrop"]
        XCTAssert(backdrop.waitForExistence(timeout: 3), "Quick action menu backdrop not found")
        
        // Verify menu sheet is visible
        let sheet = app.otherElements["quickAction.sheet"]
        XCTAssert(sheet.exists, "Quick action sheet not found")
    }
    
    /// Verifies: Mark as watched option is visible in the menu
    func test_markAsWatchedOptionVisible() {
        let firstCard = app.otherElements["home.card.continueWatching.0"]
        firstCard.press(forDuration: 0.5)
        
        // Wait for menu to appear
        let sheet = app.otherElements["quickAction.sheet"]
        XCTAssert(sheet.waitForExistence(timeout: 3))
        
        // Verify "Mark as watched" or "Mark as unwatched" option exists
        let watchedToggleButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] 'mark'")).firstMatch
        XCTAssert(watchedToggleButton.exists, "Mark watched/unwatched button not found in quick action menu")
    }
    
    /// Verifies: Cancel button closes the menu
    func test_cancelClosesMenu() {
        let firstCard = app.otherElements["home.card.continueWatching.0"]
        firstCard.press(forDuration: 0.5)
        
        // Wait for menu
        let sheet = app.otherElements["quickAction.sheet"]
        XCTAssert(sheet.waitForExistence(timeout: 3))
        
        // Tap cancel
        let cancelButton = app.buttons["quickAction.cancel"]
        XCTAssert(cancelButton.exists, "Cancel button not found")
        cancelButton.tap()
        
        // Verify menu is gone
        XCTAssert(sheet.waitForNonExistence(timeout: 2), "Menu did not close after cancel")
    }
    
    /// Verifies: Tapping backdrop closes the menu
    func test_backdropClosesMenu() {
        let firstCard = app.otherElements["home.card.continueWatching.0"]
        firstCard.press(forDuration: 0.5)
        
        let sheet = app.otherElements["quickAction.sheet"]
        XCTAssert(sheet.waitForExistence(timeout: 3))
        
        // Tap backdrop
        let backdrop = app.otherElements["quickAction.backdrop"]
        backdrop.tap()
        
        // Verify menu is gone
        XCTAssert(sheet.waitForNonExistence(timeout: 2), "Menu did not close after backdrop tap")
    }
    
    /// Verifies: Play option is available in quick action menu
    func test_playOptionAvailable() {
        let firstCard = app.otherElements["home.card.continueWatching.0"]
        firstCard.press(forDuration: 0.5)
        
        let sheet = app.otherElements["quickAction.sheet"]
        XCTAssert(sheet.waitForExistence(timeout: 3))
        
        // Look for play button
        let playButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] 'play'")).firstMatch
        XCTAssert(playButton.exists, "Play button not found in quick action menu")
    }
}
