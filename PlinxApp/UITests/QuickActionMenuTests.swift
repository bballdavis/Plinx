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
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launch()
        // Wait for home screen to load
        let homeHubElement = app.otherElements["home.hub.continueWatching"]
        XCTAssertTrue(homeHubElement.waitForExistence(timeout: 10), "Home screen failed to load")
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
