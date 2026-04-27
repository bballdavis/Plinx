import XCTest

final class LiveOfflineReconnectUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["--ui-testing", "--disable-animations"]
        app.launchEnvironment["PLINX_UI_TEST_MODE"] = "live"
        app.launchEnvironment["PLINX_UI_TEST_SCREEN"] = "liveOfflineReconnect"

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

    func test_livePullToRefreshClearsForcedOfflineState() throws {
        guard isLiveEnvironmentConfigured else {
            throw XCTSkip("Live Plex credentials are not configured. Update test_creds.yaml with PLINX_PLEX_SERVER_URL and PLINX_PLEX_TOKEN.")
        }

        let offlineScrollView = app.descendants(matching: .any)["offline.home.scroll"]
        assertElementAppears(offlineScrollView, timeout: 60, description: "offline home scroll view")

        performPullToRefresh(on: offlineScrollView)

        let onlineMarker = app.descendants(matching: .any)["liveOfflineReconnect.state.online"]
        assertOnlineMarkerAppears(onlineMarker, timeout: 45)
    }

    private func performPullToRefresh(on element: XCUIElement) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let finish = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
        start.press(forDuration: 0.12, thenDragTo: finish)
    }

    private var isLiveEnvironmentConfigured: Bool {
        let hasServer = !(resolvedCredential(named: "PLINX_PLEX_SERVER_URL") ?? "").isEmpty
        let hasToken = !(resolvedCredential(named: "PLINX_PLEX_TOKEN") ?? "").isEmpty
        return hasServer && hasToken
    }

    private func resolvedCredential(named key: String) -> String? {
        let env = ProcessInfo.processInfo.environment
        if let value = env[key], !value.isEmpty {
            return value
        }
        return yamlCredential(named: key)
    }

    private func yamlCredential(named key: String) -> String? {
        guard let yamlPath = locateTestCredsYAML(),
              let content = try? String(contentsOfFile: yamlPath, encoding: .utf8) else {
            return nil
        }

        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: ":") else {
                continue
            }

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

        let fileManager = FileManager.default
        var current = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        for _ in 0..<6 {
            let candidate = current.appendingPathComponent("test_creds.yaml").path
            if fileManager.fileExists(atPath: candidate) {
                return candidate
            }
            current.deleteLastPathComponent()
        }

        var sourceURL = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            sourceURL.deleteLastPathComponent()
        }
        let sourceCandidate = sourceURL.appendingPathComponent("test_creds.yaml").path
        if fileManager.fileExists(atPath: sourceCandidate) {
            return sourceCandidate
        }

        return nil
    }

    private func assertOnlineMarkerAppears(_ onlineMarker: XCUIElement, timeout: TimeInterval) {
        if !onlineMarker.waitForExistence(timeout: timeout) {
            print(app.debugDescription)
            let debugProbe = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "liveOfflineReconnect.debug.")
            ).firstMatch
            XCTFail("Expected online marker. Debug probe: \(debugProbe.identifier)")
            return
        }
    }

    private func assertElementAppears(
        _ element: XCUIElement,
        timeout: TimeInterval,
        description: String
    ) {
        if !element.waitForExistence(timeout: timeout) {
            print(app.debugDescription)
            let debugProbe = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "liveOfflineReconnect.debug.")
            ).firstMatch
            XCTFail("Expected \(description). Debug probe: \(debugProbe.identifier)")
            return
        }
    }
}