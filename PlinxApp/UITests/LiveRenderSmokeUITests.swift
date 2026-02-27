import XCTest
import Foundation

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
        for key in keys {
            if let value = resolvedCredential(named: key), !value.isEmpty {
                app.launchEnvironment[key] = value
            }
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

    func test_liveQuickActionSheet_containsPlayableButtons() throws {
        try longPressFirstHomeCardForQuickActions()

        let quickSheet = app.otherElements["quickAction.sheet"]
        XCTAssertTrue(quickSheet.waitForExistence(timeout: 8), "Quick-action sheet should appear after long press")

        XCTAssertTrue(app.buttons["quickAction.option.play"].exists,
                      "Playable quick-action sheet should show Play")
        XCTAssertTrue(app.buttons["quickAction.option.go-details"].exists,
                      "Playable quick-action sheet should show Go to details")
    }

    func test_liveQuickAction_goToDetails_opensDetailWithoutErrorAlert() throws {
        try longPressFirstHomeCardForQuickActions()

        let detailsButton = app.buttons["quickAction.option.go-details"]
        XCTAssertTrue(detailsButton.waitForExistence(timeout: 8), "Go to details action should be present")
        detailsButton.tap()

        let detailScreen = app.otherElements["media.detail.screen"]
        XCTAssertTrue(detailScreen.waitForExistence(timeout: 15),
                      "Media detail screen should appear after tapping Go to details")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 3),
                  "App should remain running after quick-action Go to details")

        let actionFailedAlert = app.alerts["Action Failed"]
        XCTAssertFalse(actionFailedAlert.exists,
                       "Action Failed alert should not be shown when Go to details succeeds")
    }

    private var isLiveEnvironmentConfigured: Bool {
        let hasServer = !(resolvedCredential(named: "PLINX_PLEX_SERVER_URL") ?? "").isEmpty
        let hasToken = !(resolvedCredential(named: "PLINX_PLEX_TOKEN") ?? "").isEmpty
        let hasUserPass = !(resolvedCredential(named: "PLINX_PLEX_USER") ?? "").isEmpty
            && !(resolvedCredential(named: "PLINX_PLEX_PASSWORD") ?? "").isEmpty
        let hasPin = !(resolvedCredential(named: "PLINX_PLEX_PIN") ?? "").isEmpty
        return hasServer && (hasToken || hasUserPass || hasPin)
    }

    private func resolvedCredential(named key: String) -> String? {
        let env = ProcessInfo.processInfo.environment
        if let value = env[key], !value.isEmpty {
            return value
        }
        return yamlCredential(named: key)
    }

    private func yamlCredential(named key: String) -> String? {
        guard
            let yamlPath = locateTestCredsYAML(),
            let content = try? String(contentsOfFile: yamlPath, encoding: .utf8)
        else {
            return nil
        }

        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let separator = line.firstIndex(of: ":") else { continue }

            let parsedKey = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard parsedKey == key else { continue }

            var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            } else if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private func locateTestCredsYAML() -> String? {
        if let bundledPath = Bundle(for: Self.self)
            .url(forResource: "test_creds", withExtension: "yaml")?
            .path {
            return bundledPath
        }

        let fm = FileManager.default
        var current = URL(fileURLWithPath: fm.currentDirectoryPath)

        for _ in 0..<6 {
            let candidate = current.appendingPathComponent("test_creds.yaml").path
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
            current.deleteLastPathComponent()
        }

        // Fallback from source path:
        // <repo>/PlinxApp/UITests/LiveRenderSmokeUITests.swift
        // -> <repo>/test_creds.yaml
        var sourceURL = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { sourceURL.deleteLastPathComponent() }
        let sourceCandidate = sourceURL.appendingPathComponent("test_creds.yaml").path
        if fm.fileExists(atPath: sourceCandidate) {
            return sourceCandidate
        }

        return nil
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

    private func longPressFirstHomeCardForQuickActions() throws {
        let cardCandidates = [
            "home.card.moviesAndTV.0",
            "home.card.otherVideos.0",
        ]

        for identifier in cardCandidates {
            let card = app.otherElements[identifier]
            if card.waitForExistence(timeout: 20), card.isHittable {
                card.press(forDuration: 1.1)
                return
            }
        }

        if try longPressFirstLibraryBrowseItemForQuickActions() {
            return
        }

        throw XCTSkip("No home cards were available for quick-action long-press test.")
    }

    private func longPressFirstLibraryBrowseItemForQuickActions() throws -> Bool {
        let libraryTab = app.tabBars.buttons["Library"]
        guard libraryTab.waitForExistence(timeout: 8) else { return false }
        libraryTab.tap()

        let firstLibraryTile = app.buttons.firstMatch
        guard firstLibraryTile.waitForExistence(timeout: 8), firstLibraryTile.isHittable else {
            return false
        }
        firstLibraryTile.tap()

        let browseTab = app.buttons["library.detail.tab.browse"]
        if browseTab.waitForExistence(timeout: 8), browseTab.isHittable {
            browseTab.tap()
        }

        let browseItem = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.browse.item."))
            .firstMatch

        guard browseItem.waitForExistence(timeout: 12), browseItem.isHittable else {
            return false
        }

        browseItem.press(forDuration: 1.1)
        return true
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
