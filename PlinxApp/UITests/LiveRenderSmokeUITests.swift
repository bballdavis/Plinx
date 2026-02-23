import XCTest

final class LiveRenderSmokeUITests: XCTestCase {

    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false

        app.launchArguments += ["--ui-testing", "--disable-animations"]
        app.launchEnvironment["PLINX_UI_TEST_MODE"] = "live"

        // Forward live Plex vars from test runner env → app env (if provided)
        let keys = [
            "PLINX_PLEX_SERVER_URL",
            "PLINX_PLEX_TOKEN",
            "PLINX_PLEX_USER",
            "PLINX_PLEX_PASSWORD",
            "PLINX_PLEX_PIN"
        ]
        let environment = ProcessInfo.processInfo.environment
        for key in keys where environment[key] != nil {
            app.launchEnvironment[key] = environment[key]
        }

        app.launch()
    }

    func test_liveHomeRendersPrimarySections() throws {
        guard isLiveEnvironmentConfigured else {
            throw XCTSkip("Live Plex credentials are not configured. Update test_creds.yaml with PLINX_PLEX_SERVER_URL and PLINX_PLEX_TOKEN.")
        }

        // We expect at least one core section to appear when live content loads.
        // Accept either exact section IDs or localized static titles as fallback.
        let continueSection = app.otherElements["home.hub.continueWatching"]
        let moviesSection = app.otherElements.matching(identifier: "home.hub.moviesAndTV").firstMatch
        let otherSection = app.otherElements.matching(identifier: "home.hub.otherVideos").firstMatch

        let localizedContinue = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Continue")).firstMatch
        let localizedRecent = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Recent")).firstMatch

        let loaded = waitForAny([
            continueSection,
            moviesSection,
            otherSection,
            localizedContinue,
            localizedRecent
        ], timeout: 40)

        if !loaded {
            attachScreenshot(name: "live-home-not-loaded")
        }
        XCTAssertTrue(loaded, "Expected at least one live home section to render.")
    }

    func test_liveOtherVideosThumbnailIsLandscape() throws {
        guard isLiveEnvironmentConfigured else {
            throw XCTSkip("Live Plex env vars are not configured.")
        }

        let otherRow = app.otherElements["home.hub.otherVideos"]
        XCTAssertTrue(otherRow.waitForExistence(timeout: 40), "Other Videos section did not render")

        let otherThumb = app.otherElements["home.thumbnail.otherVideos.0"]
        XCTAssertTrue(otherThumb.waitForExistence(timeout: 15), "Expected first thumbnail in Other Videos section")

        let ratio = aspectRatio(of: otherThumb)
        if ratio <= 1.2 {
            attachScreenshot(name: "other-videos-not-landscape")
        }
        XCTAssertGreaterThan(ratio, 1.2, "Other Videos thumbnail should be landscape (width > height)")
    }

    func test_liveMovieThumbnailIsPortrait() throws {
        guard isLiveEnvironmentConfigured else {
            throw XCTSkip("Live Plex env vars are not configured.")
        }

        let moviesRow = app.otherElements["home.hub.moviesAndTV"]
        XCTAssertTrue(moviesRow.waitForExistence(timeout: 40), "Movies/TV section did not render")

        let movieThumb = app.otherElements["home.thumbnail.moviesAndTV.0"]
        XCTAssertTrue(movieThumb.waitForExistence(timeout: 15), "Expected first thumbnail in Movies/TV section")

        let ratio = aspectRatio(of: movieThumb)
        if ratio >= 1.0 {
            attachScreenshot(name: "movie-not-portrait")
        }
        XCTAssertLessThan(ratio, 1.0, "Movies/TV thumbnail should be portrait (height > width)")
    }

    func test_liveLandscapeAndPortraitDiffer() throws {
        guard isLiveEnvironmentConfigured else {
            throw XCTSkip("Live Plex env vars are not configured.")
        }

        let otherThumb = app.otherElements["home.thumbnail.otherVideos.0"]
        let movieThumb = app.otherElements["home.thumbnail.moviesAndTV.0"]

        XCTAssertTrue(otherThumb.waitForExistence(timeout: 40), "Other Videos thumbnail missing")
        XCTAssertTrue(movieThumb.waitForExistence(timeout: 20), "Movies/TV thumbnail missing")

        let otherRatio = aspectRatio(of: otherThumb)
        let movieRatio = aspectRatio(of: movieThumb)

        if abs(otherRatio - movieRatio) < 0.4 {
            attachScreenshot(name: "layout-ratios-too-similar")
        }

        XCTAssertGreaterThan(otherRatio, movieRatio + 0.4,
                             "Landscape thumbnail ratio should be significantly wider than portrait ratio")
    }

    private var isLiveEnvironmentConfigured: Bool {
        let env = ProcessInfo.processInfo.environment
        let hasServer = !(env["PLINX_PLEX_SERVER_URL"] ?? "").isEmpty
        let hasToken = !(env["PLINX_PLEX_TOKEN"] ?? "").isEmpty
        let hasUserPass = !(env["PLINX_PLEX_USER"] ?? "").isEmpty && !(env["PLINX_PLEX_PASSWORD"] ?? "").isEmpty
        let hasPin = !(env["PLINX_PLEX_PIN"] ?? "").isEmpty
        return hasServer && (hasToken || hasUserPass || hasPin)
    }

    private func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: { $0.exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }

    private func aspectRatio(of element: XCUIElement) -> CGFloat {
        let frame = element.frame
        guard frame.height > 0 else { return 0 }
        return frame.width / frame.height
    }

    private func attachScreenshot(name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
