import XCTest

final class PlayerTimelineUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        #if !os(tvOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
    }

    func test_fullPlayerOverlayShowsTimeline() {
        let app = launch(position: 50, fullOverlay: true)
        let timeline = timeline(in: app)
        XCTAssertGreaterThan(timeline.frame.width, 100)
        XCTAssertGreaterThanOrEqual(timeline.frame.height, 64)
        capture("timeline-full-player-overlay")
    }

    #if os(tvOS)
    func test_remoteCommitsAndCanLeaveFocus() {
        let app = launch(position: 50)
        let timeline = timeline(in: app)
        expect(timeline, "hasFocus == true")
        XCUIRemote.shared.press(.right)
        expect(app.staticTexts["timeline.fixture.commits"], "value == '1'")
        XCTAssertEqual(metric("position", in: app), "55.00")
        XCTAssertEqual(metric("begins", in: app), "1")
        XCTAssertEqual(metric("scrubbing", in: app), "no")
        XCUIRemote.shared.press(.down)
        expect(app.buttons["timeline.fixture.hide"], "hasFocus == true")
        XCTAssertEqual(metric("commits", in: app), "1")
    }

    func test_remoteClampsAtBothEndpoints() {
        for initial in [0, 100] {
            let app = launch(position: initial)
            let timeline = timeline(in: app)
            expect(timeline, "hasFocus == true")
            capture("timeline-tv-\(initial)")
            XCUIRemote.shared.press(initial == 0 ? .left : .right)
            XCTAssertEqual(metric("position", in: app), String(format: "%.2f", Double(initial)))
            XCTAssertEqual(metric("begins", in: app), "0")
            XCUIRemote.shared.press(initial == 0 ? .right : .left)
            expect(app.staticTexts["timeline.fixture.commits"], "value == '1'")
            XCTAssertEqual(metric("position", in: app), initial == 0 ? "5.00" : "95.00")
            app.terminate()
        }
    }
    #else
    func test_fullPlayerOverlayLandscape() {
        let app = launch(position: 50, fullOverlay: true, landscape: true)
        let timeline = timeline(in: app)
        let window = app.windows.firstMatch
        XCTAssertGreaterThan(window.frame.width, window.frame.height)
        XCTAssertGreaterThanOrEqual(timeline.frame.minX, window.frame.minX)
        XCTAssertLessThanOrEqual(timeline.frame.maxX, window.frame.maxX)
        XCTAssertLessThanOrEqual(timeline.frame.maxY, window.frame.maxY)
        capture("timeline-full-player-landscape")
    }

    func test_trackAndHandleTapsDoNotSeek() {
        let app = launch(position: 50)
        let timeline = timeline(in: app)
        point(timeline, x: 0.15).tap()
        point(timeline, x: 0.5).tap()
        XCTAssertEqual(metric("position", in: app), "50.00")
        XCTAssertEqual(metric("begins", in: app), "0")
        XCTAssertEqual(metric("commits", in: app), "0")
        capture("timeline-touch-middle")
    }

    func test_handleDragCommitsOnceAndReachesBothEndpoints() {
        let app = launch(position: 50)
        let timeline = timeline(in: app)
        point(timeline, x: 0.5).press(forDuration: 0.1, thenDragTo: point(timeline, x: 1.05))
        expect(app.staticTexts["timeline.fixture.position"], "value == '100.00'")
        XCTAssertEqual(metric("begins", in: app), "1")
        XCTAssertEqual(metric("commits", in: app), "1")
        XCTAssertEqual(metric("scrubbing", in: app), "no")
        capture("timeline-touch-end")

        // Grab inside the enlarged endpoint target, away from its true center.
        point(timeline, x: 1, offset: -20).press(
            forDuration: 0.1, thenDragTo: point(timeline, x: 0, offset: -30)
        )
        expect(app.staticTexts["timeline.fixture.position"], "value == '0.00'")
        XCTAssertEqual(metric("begins", in: app), "2")
        XCTAssertEqual(metric("commits", in: app), "2")
        capture("timeline-touch-start")
    }

    func test_beginningHandleCanBeGrabbedFromInsideTrack() {
        let app = launch(position: 0)
        let timeline = timeline(in: app)
        point(timeline, x: 0, offset: 24).press(
            forDuration: 0.1, thenDragTo: point(timeline, x: 0.5, offset: 24)
        )
        capture("timeline-after-offset-drag")
        expect(app.staticTexts["timeline.fixture.commits"], "value == '1'")
        let result = Double(metric("position", in: app)) ?? -1
        XCTAssertEqual(result, 50, accuracy: 2)
    }

    func test_unknownDurationDisablesDragging() {
        let app = launch(position: 50, unavailable: true)
        let timeline = timeline(in: app)
        XCTAssertEqual(timeline.value as? String, "Seeking unavailable")
        point(timeline, x: 0.5).press(forDuration: 0.1, thenDragTo: point(timeline, x: 0.8))
        XCTAssertEqual(metric("commits", in: app), "0")
        XCTAssertEqual(metric("begins", in: app), "0")
        capture("timeline-touch-unavailable")
    }

    private func point(_ element: XCUIElement, x: CGFloat, offset: CGFloat = 0) -> XCUICoordinate {
        element.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5))
            .withOffset(CGVector(dx: offset, dy: 0))
    }
    #endif

    private func launch(position: Int, unavailable: Bool = false, fullOverlay: Bool = false, landscape: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--disable-animations"]
        if landscape { app.launchArguments += ["--app-store-landscape"] }
        app.launchEnvironment["PLINX_UI_TEST_SCREEN"] = "playerTimeline"
        app.launchEnvironment["PLINX_TIMELINE_POSITION"] = String(position)
        app.launchEnvironment["PLINX_TIMELINE_UNAVAILABLE"] = unavailable ? "1" : "0"
        app.launchEnvironment["PLINX_TIMELINE_OVERLAY"] = fullOverlay ? "1" : "0"
        app.launch()
        return app
    }

    private func timeline(in app: XCUIApplication) -> XCUIElement {
        let element = app.descendants(matching: .any)["player.timeline"].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(element.frame.width, 100)
        XCTAssertGreaterThanOrEqual(element.frame.height, 64)
        let details = XCTAttachment(string: element.debugDescription)
        details.name = "Timeline accessibility frame"
        details.lifetime = .keepAlways
        add(details)
        return element
    }

    private func metric(_ name: String, in app: XCUIApplication) -> String {
        app.staticTexts["timeline.fixture.\(name)"].value as? String ?? "missing"
    }

    private func expect(_ element: XCUIElement, _ predicate: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func capture(_ name: String) {
        // AX can settle before the simulator has presented the final rotation
        // frame. Let that frame reach the compositor before taking evidence.
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
