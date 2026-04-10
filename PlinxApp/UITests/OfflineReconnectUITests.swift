import XCTest

final class OfflineReconnectUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["--ui-testing", "--disable-animations"]
        app.launchEnvironment["PLINX_UI_TEST_SCREEN"] = "offlineReconnect"
        app.launch()
    }

    func test_pullToRefreshOnOfflineHomeReturnsToOnlineMode() throws {
        let offlineScrollView = app.descendants(matching: .any)["offline.home.scroll"]

        XCTAssertTrue(offlineScrollView.waitForExistence(timeout: 8))

        performPullToRefresh(on: offlineScrollView)

        let onlineMarker = app.descendants(matching: .any)["offlineReconnect.state.online"]
        assertOnlineMarkerAppears(onlineMarker)
    }

    func test_directReconnectTriggerReturnsToOnlineMode() throws {
        let reconnectTrigger = app.buttons["offlineReconnect.trigger"]

        XCTAssertTrue(reconnectTrigger.waitForExistence(timeout: 8))
        reconnectTrigger.tap()

        let onlineMarker = app.descendants(matching: .any)["offlineReconnect.state.online"]
        assertOnlineMarkerAppears(onlineMarker)
    }

    func test_pullToRefreshOnOfflineDownloadsReturnsToOnlineMode() throws {
        let downloadsTab = app.buttons["main.tab.downloads"]
        assertElementAppears(downloadsTab, timeout: 8, description: "downloads tab")
        downloadsTab.tap()

        let downloadsScrollView = app.descendants(matching: .any)["downloads.grid.scroll"]
        assertElementAppears(downloadsScrollView, timeout: 8, description: "downloads scroll view")

        performPullToRefresh(on: downloadsScrollView)

        let onlineMarker = app.descendants(matching: .any)["offlineReconnect.state.online"]
        assertOnlineMarkerAppears(onlineMarker)
    }

    private func performPullToRefresh(on element: XCUIElement) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let finish = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
        start.press(forDuration: 0.12, thenDragTo: finish)
    }

    private func assertOnlineMarkerAppears(_ onlineMarker: XCUIElement, timeout: TimeInterval = 8) {
        if !onlineMarker.waitForExistence(timeout: timeout) {
            print(app.debugDescription)
            let debugProbe = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "offlineReconnect.debug.")
            ).firstMatch
            XCTAssertTrue(false, "Expected online marker. Debug probe: \(debugProbe.identifier)")
            return
        }

        XCTAssertTrue(true)
    }

    private func assertElementAppears(
        _ element: XCUIElement,
        timeout: TimeInterval,
        description: String,
    ) {
        if !element.waitForExistence(timeout: timeout) {
            print(app.debugDescription)
            let debugProbe = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "offlineReconnect.debug.")
            ).firstMatch
            XCTAssertTrue(false, "Expected \(description). Debug probe: \(debugProbe.identifier)")
            return
        }

        XCTAssertTrue(true)
    }
}