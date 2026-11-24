import XCTest

/// Developer tool: replays a scripted Siri Remote walk against the
/// credential-free demo library and captures a screenshot plus the focused
/// element after each press. Skipped unless a walk is supplied, e.g.
///
///     TEST_RUNNER_PLINX_REMOTE_WALK="down,right,select,wait,menu" \
///       xcodebuild test-without-building ... \
///       -only-testing:PlinxTVUITests/AppleTVRemoteWalkUITests
///
/// Steps: up, down, left, right, select, menu, playPause, home, hold (long
/// Select), wait (1.5s). Set TEST_RUNNER_PLINX_REMOTE_WALK_DIR to also write
/// each screenshot to a simulator-host directory as it is taken.
final class AppleTVRemoteWalkUITests: XCTestCase {
    func test_remoteWalk() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let script = environment["PLINX_REMOTE_WALK"], !script.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_PLINX_REMOTE_WALK to run a remote walk.")
        }

        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--disable-animations"]
        app.launchEnvironment["PLINX_UI_TEST_MODE"] = "demo"
        app.launch()

        XCTAssertTrue(
            app.buttons["main.tab.home"].waitForExistence(timeout: 30),
            "Demo mode should reach the browsing shell"
        )
        sleep(2)
        record(app, step: 0, label: "start")

        let steps = script.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for (index, step) in steps.enumerated() {
            switch step {
            case "up": XCUIRemote.shared.press(.up)
            case "down": XCUIRemote.shared.press(.down)
            case "left": XCUIRemote.shared.press(.left)
            case "right": XCUIRemote.shared.press(.right)
            case "select": XCUIRemote.shared.press(.select)
            case "menu": XCUIRemote.shared.press(.menu)
            case "playPause": XCUIRemote.shared.press(.playPause)
            case "home": XCUIRemote.shared.press(.home)
            case "hold": XCUIRemote.shared.press(.select, forDuration: 1.2)
            case "wait": Thread.sleep(forTimeInterval: 1.5)
            default: XCTFail("Unknown remote step \(step)")
            }
            Thread.sleep(forTimeInterval: 0.9)
            record(app, step: index + 1, label: step)
        }
    }

    private func record(_ app: XCUIApplication, step: Int, label: String) {
        let focused = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true"))
            .firstMatch
        let focusDescription = focused.exists
            ? "\(focused.elementType.rawValue) id=\(focused.identifier) label=\(focused.label)"
            : "none"
        print("PLINX_WALK step=\(step) action=\(label) focus=\(focusDescription)")

        let screenshot = XCUIScreen.main.screenshot()
        let name = String(format: "walk-%02d-%@", step, label)
        if let directory = ProcessInfo.processInfo.environment["PLINX_REMOTE_WALK_DIR"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
