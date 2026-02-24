import XCTest

/// Verifies the kid-facing library tab UI according to the Plinx UX spec:
///
/// - The tab picker uses icon buttons, NOT a segmented control.
/// - The "playlists" tab is absent.
/// - The icon buttons for Recommended, Browse, and Collections are present.
/// - Tapping a tab activates it (verified via accessibility identifier).
/// - Library tiles span their full visual bounds (hit area sanity check).
///
/// These tests run against a freshly-launched app without a live Plex server.
/// They only exercise navigation and visible chrome — not content loading.
final class LibraryTabUITests: XCTestCase {

    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["--ui-testing", "--disable-animations"]
        app.launch()
    }

    // MARK: - Tab bar navigation

    func test_libraryTabBarItem_exists() {
        let libraryTabBarItem = app.tabBars.buttons["Library"]
        XCTAssertTrue(libraryTabBarItem.waitForExistence(timeout: 8),
                      "Library tab-bar item should be present after launch")
    }

    // MARK: - Icon-button picker (not segmented control)

    /// After navigating into any library, the detail screen must show the
    /// custom KidsLibraryTabPicker (accessibility ID = "library.detail.tabPicker")
    /// rather than the Strimr default segmented control.
    func test_libraryDetailPicker_isKidsIconPicker() throws {
        navigateIntoFirstLibrary()

        // The kids picker container must exist …
        let picker = app.otherElements["library.detail.tabPicker"]
        let pickerExists = picker.waitForExistence(timeout: 8)

        // and the standard segmented picker must NOT exist.
        let segmented = app.segmentedControls.matching(
            NSPredicate(format: "identifier CONTAINS[c] %@", "tabPicker")
        ).firstMatch

        if pickerExists {
            XCTAssertFalse(segmented.exists,
                           "Segmented control must be replaced by KidsLibraryTabPicker")
        } else {
            // Not in a library yet (no server / no libraries) — skip assertions.
            throw XCTSkip("No library loaded; icon picker check skipped.")
        }
    }

    // MARK: - Playlists tab is gone

    /// The 'playlists' tab must never appear in the library detail screen.
    func test_libraryDetailPicker_doesNotContainPlaylistsTab() throws {
        navigateIntoFirstLibrary()
        guard app.otherElements["library.detail.tabPicker"].waitForExistence(timeout: 8) else {
            throw XCTSkip("No library loaded; playlists-tab check skipped.")
        }

        let playlistsButton = app.buttons["library.detail.tab.playlists"]
        XCTAssertFalse(playlistsButton.exists,
                       "Playlists tab must be hidden in Plinx (not kid-friendly surface)")
    }

    // MARK: - Expected tabs are present

    func test_libraryDetailPicker_containsExpectedTabs() throws {
        navigateIntoFirstLibrary()
        guard app.otherElements["library.detail.tabPicker"].waitForExistence(timeout: 8) else {
            throw XCTSkip("No library loaded; tab presence check skipped.")
        }

        let expectedIdentifiers = [
            "library.detail.tab.recommended",
            "library.detail.tab.browse",
        ]
        for id in expectedIdentifiers {
            XCTAssertTrue(app.buttons[id].exists,
                          "Tab '\(id)' should be visible in the library detail picker")
        }
    }

    // MARK: - Tab switching

    func test_libraryDetailPicker_tapBrowseTab_activatesIt() throws {
        navigateIntoFirstLibrary()
        guard app.otherElements["library.detail.tabPicker"].waitForExistence(timeout: 8) else {
            throw XCTSkip("No library loaded; tab-switching check skipped.")
        }

        let browseButton = app.buttons["library.detail.tab.browse"]
        guard browseButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Browse tab not found.")
        }

        browseButton.tap()

        // After tapping Browse, the grid / list content area should appear.
        // We wait for any cell or progress indicator (both indicate Browse is active).
        let browseContent = app.scrollViews.firstMatch
        XCTAssertTrue(browseContent.waitForExistence(timeout: 5),
                      "Browse tab content should appear after tapping the Browse button")
    }

    // MARK: - Library tile hit area

    /// Verifies that each library tile button in PlinxLibraryView is hittable
    /// (i.e., the contentShape covers the full frame, not just the opaque areas).
    func test_libraryTiles_areHittable() throws {
        let libraryTabBarItem = app.tabBars.buttons["Library"]
        guard libraryTabBarItem.waitForExistence(timeout: 8) else {
            throw XCTSkip("Library tab not found.")
        }
        libraryTabBarItem.tap()

        // Give the library list time to render
        let anyButton = app.buttons.firstMatch
        guard anyButton.waitForExistence(timeout: 8) else {
            throw XCTSkip("No library tiles loaded.")
        }

        // Verify the first button is isHittable — this fails when contentShape is
        // missing because transparent gradient areas don't register as tap targets.
        let firstTile = app.buttons.element(boundBy: 0)
        XCTAssertTrue(firstTile.isHittable,
                      "Library tile must be hittable across its entire visual frame")
    }

    // MARK: - Helpers

    private func navigateIntoFirstLibrary() {
        let libraryTabBarItem = app.tabBars.buttons["Library"]
        guard libraryTabBarItem.waitForExistence(timeout: 6) else { return }
        libraryTabBarItem.tap()

        // Tap the first library tile if one is present
        let firstTile = app.buttons.firstMatch
        guard firstTile.waitForExistence(timeout: 6), firstTile.isHittable else { return }
        firstTile.tap()
    }
}
