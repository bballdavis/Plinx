import XCTest

/// Verifies Plinx home-screen section grouping according to spec:
///
/// - Movies and TV are combined in a single "moviesAndTV" row.
/// - Other-Video / Home-Video / Clip libraries appear as their **own** separate
///   row(s) under the "otherVideos" section — NOT merged into movies+TV.
/// - The landscape (letterbox) thumbnail style is used for Other Video rows.
///
/// These tests require a live Plex server. They are automatically skipped when
/// the live environment is not configured (PLINX_PLEX_SERVER_URL + TOKEN).
final class HomeScreenSectionUITests: XCTestCase {

    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["--ui-testing", "--disable-animations"]
        app.launchEnvironment["PLINX_UI_TEST_MODE"] = "live"

        let keys = [
            "PLINX_PLEX_SERVER_URL",
            "PLINX_PLEX_TOKEN",
            "PLINX_PLEX_USER",
            "PLINX_PLEX_PASSWORD",
            "PLINX_PLEX_PIN",
        ]
        let env = ProcessInfo.processInfo.environment
        for key in keys where env[key] != nil {
            app.launchEnvironment[key] = env[key]
        }
        app.launch()
    }

    private var isLiveEnvironmentConfigured: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["PLINX_PLEX_SERVER_URL"] != nil && env["PLINX_PLEX_TOKEN"] != nil
    }

    // MARK: - Section separation

    /// Verifies that at least one recently-added section renders on the Home tab.
    func test_homeScreen_rendersAtLeastOneSection() throws {
        guard isLiveEnvironmentConfigured else {
            throw XCTSkip("Live Plex credentials not configured.")
        }

        let moviesSection  = app.otherElements["home.hub.moviesAndTV"]
        let otherSection   = app.otherElements["home.hub.otherVideos"]
        let continueSection = app.otherElements["home.hub.continueWatching"]

        let loaded = [moviesSection, otherSection, continueSection].contains {
            $0.waitForExistence(timeout: 40)
        }
        XCTAssertTrue(loaded, "At least one home section must render")
    }

    /// Verifies that Other-Video rows (if present) appear under the "otherVideos"
    /// accessibility hub — meaning they are NOT merged into the movies+TV row.
    func test_homeScreen_otherVideosAreNotMergedIntoMoviesRow() throws {
        guard isLiveEnvironmentConfigured else {
            throw XCTSkip("Live Plex credentials not configured.")
        }

        // Wait for the home screen to load
        let homeScreen = app.otherElements["home.hub.moviesAndTV"]
            .firstMatch
        _ = homeScreen.waitForExistence(timeout: 40)

        let otherHub = app.otherElements["home.hub.otherVideos"]

        // If an otherVideos hub is rendered, it must be a *separate* element from
        // moviesAndTV — any overlap in their frames would indicate incorrect merging.
        if otherHub.exists {
            let moviesHub = app.otherElements["home.hub.moviesAndTV"]
            if moviesHub.exists {
                let moviesFrame = moviesHub.frame
                let otherFrame  = otherHub.frame
                XCTAssertFalse(
                    moviesFrame.intersects(otherFrame),
                    "otherVideos hub must be a distinct row, not overlapping moviesAndTV"
                )
            }
            // Additionally, the otherVideos section title must NOT contain "Movies"
            // (which would indicate incorrect merging of clip content into the movie row)
            let sectionTitleText = app.staticTexts
                .matching(NSPredicate(format: "identifier CONTAINS[c] %@", "home.section.otherVideos"))
                .firstMatch
            if sectionTitleText.exists {
                let label = sectionTitleText.label.lowercased()
                XCTAssertFalse(
                    label.contains("movie") && !label.contains("other"),
                    "otherVideos section title should not be the movies title: '\(sectionTitleText.label)'"
                )
            }
        }
    }

    /// Verifies that the movies+TV row uses portrait (tall) thumbnails and
    /// the otherVideos row uses landscape (wide) thumbnails.
    func test_homeScreen_thumbnailAspectRatioMatchesContentType() throws {
        guard isLiveEnvironmentConfigured else {
            throw XCTSkip("Live Plex credentials not configured.")
        }

        _ = app.otherElements["home.hub.moviesAndTV"].waitForExistence(timeout: 40)

        // Movies+TV thumbnails: portrait cards are taller than wide (ratio < 1)
        let movieCard = app.images["home.thumbnail.moviesAndTV.0"]
        if movieCard.exists {
            let frame = movieCard.frame
            if frame.width > 0, frame.height > 0 {
                XCTAssertGreaterThan(frame.height, frame.width,
                    "Movies+TV thumbnails should be portrait (height > width)")
            }
        }

        // OtherVideos thumbnails: landscape cards are wider than tall (ratio > 1)
        let otherCard = app.images["home.thumbnail.otherVideos.0"]
        if otherCard.exists {
            let frame = otherCard.frame
            if frame.width > 0, frame.height > 0 {
                XCTAssertGreaterThan(frame.width, frame.height,
                    "Other-Videos thumbnails should be landscape (width > height)")
            }
        }
    }
}
