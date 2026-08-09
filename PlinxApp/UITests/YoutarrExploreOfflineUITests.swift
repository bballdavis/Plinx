import XCTest

@MainActor
final class YoutarrExploreOfflineUITests: XCTestCase {
    private var baseURL: URL!
    private var apiKey: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        baseURL = URL(string: "http://127.0.0.1:39087")!
        apiKey = "plinx-synthetic-key"
    }

    func test_syntheticServerRendersFullExploreDetailRequestsAndRequestWrite() async throws {
        try await selectScenario("normal")
        let app = launchExplore()

        for youtubeID in ["abcdefghijk", "shortvid001", "streamvid01"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["youtarr.explore.video.\(youtubeID)"]
                    .waitForExistence(timeout: 15),
                "Expected the canonical \(youtubeID) record to render."
            )
        }
        XCTAssertFalse(
            app.descendants(matching: .any)["youtarr.explore.video.unsafe00001"].exists,
            "The defense-in-depth rating filter must hide the mature synthetic record."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["youtarr.explore.channel.8"].exists,
            "Expected the granted canonical channel to render."
        )
        let artwork = try await waitForArtworkRequests()
        XCTAssertTrue(artwork.contains("channel:8"))
        XCTAssertTrue(artwork.contains("video:abcdefghijk"))

        app.descendants(matching: .any)["youtarr.explore.video.abcdefghijk"].tap()
        XCTAssertTrue(app.otherElements["youtarr.details.screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["youtarr.details.loaded"]
                .waitForExistence(timeout: 15),
            "Expected rich metadata from the real HTTP detail endpoint."
        )
        let requestButton = app.descendants(matching: .any)["youtarr.details.request.abcdefghijk"]
        XCTAssertTrue(requestButton.waitForExistence(timeout: 10))
        requestButton.tap()
        let body = try await waitForVideoRequest()
        XCTAssertEqual(body["youtubeId"] as? String, "abcdefghijk")
        XCTAssertEqual(body["channelId"] as? Int, 8)
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(body["idempotencyKey"] as? String)))

        app.buttons["youtarr.details.close"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["youtarr.explore.video.abcdefghijk"]
                .waitForNonExistence(timeout: 10)
        )
        try await Task.sleep(for: .milliseconds(500))
        let myRequests = app.buttons["youtarr.explore.myRequests"]
        XCTAssertTrue(myRequests.waitForExistence(timeout: 10))
        myRequests.tap()
        let requestsScreen = app.otherElements["youtarr.requests.screen"]
        guard requestsScreen.waitForExistence(timeout: 15) else {
            XCTFail("My Requests did not mount.\n\(app.debugDescription)")
            return
        }
        let allRequests = app.buttons["youtarr.requests.filter.all"]
        XCTAssertTrue(allRequests.waitForExistence(timeout: 10))
        allRequests.tap()
        for requestID in [
            "00000000-0000-4000-8000-000000000098", // pending synthetic write
            "00000000-0000-4000-8000-000000000097", // unknown-safe fallback
            "00000000-0000-4000-8000-000000000017", // completed
            "00000000-0000-4000-8000-000000000016", // cancelled
            "00000000-0000-4000-8000-000000000015", // failed
            "00000000-0000-4000-8000-000000000014", // rejected
            "00000000-0000-4000-8000-000000000010", // processing
        ] {
            let row = app.descendants(matching: .any)["youtarr.requests.item.\(requestID)"]
            for _ in 0..<6 where !row.exists {
                requestsScreen.swipeUp()
            }
            XCTAssertTrue(row.exists, "Expected lifecycle fixture \(requestID) to render.")
        }
    }

    func test_emptyAndSafetyFilteredCatalogsRemainDistinct() async throws {
        try await selectScenario("empty")
        var app = launchExplore()
        XCTAssertTrue(
            app.descendants(matching: .any)["youtarr.explore.empty.noRequestableVideos"]
                .waitForExistence(timeout: 15),
            app.debugDescription
        )
        app.terminate()

        try await selectScenario("filtered")
        app = launchExplore()
        XCTAssertTrue(
            app.descendants(matching: .any)["youtarr.explore.empty.safetyPolicy"]
                .waitForExistence(timeout: 15),
            app.debugDescription
        )
    }

    func test_unauthorizedMalformedAndServerFailuresAreActionable() async throws {
        let expectations: [(String, String, Bool)] = [
            ("unauthorized", "Youtarr did not accept this API key. A parent must replace or reconfigure it in Settings.", true),
            ("transport", "Plinx could not reach Youtarr. Check the address and network.", true),
            ("unsupported", "This Youtarr external API version is not supported by Plinx.", true),
            // ContentUnavailableView does not consistently expose its action
            // identifier while presenting a decoder failure on iOS 26. The
            // distinct, body-free error copy is the contract for this case.
            ("malformed", "Youtarr sent an unexpected response.", false),
            ("server-error", "Youtarr is temporarily unavailable.", true),
        ]
        for (scenario, message, expectsRetry) in expectations {
            try await selectScenario(scenario)
            let app = launchExplore()
            XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 15), scenario)
            if expectsRetry {
                XCTAssertTrue(
                    app.descendants(matching: .any)["youtarr.explore.retry"].exists,
                    scenario
                )
            }
            app.terminate()
        }
    }

    func test_leavingDuringDelayedLoadDoesNotFlashNetworkFailure() async throws {
        try await selectScenario("normal", delayMs: 1_500)
        let app = makeApp()
        app.launch()
        let explore = app.buttons["main.tab.explore.fixture"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        explore.tap()
        app.buttons["main.tab.home.fixture"].tap()
        XCTAssertFalse(app.staticTexts["Explore Couldn’t Load"].waitForExistence(timeout: 3))
    }

    private func launchExplore() -> XCUIApplication {
        let app = makeApp()
        app.launch()
        let explore = app.buttons["main.tab.explore.fixture"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        explore.tap()
        let screen = app.otherElements["youtarr.explore.screen"]
        if !screen.waitForExistence(timeout: 3), explore.isHittable {
            // The simulator can drop the first synthesized tap while the
            // cold-launched fixture is still settling. Activation is
            // idempotent, so retry once before treating it as an app failure.
            explore.tap()
        }
        guard screen.waitForExistence(timeout: 10) else {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "missing-youtarr-explore-screen"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTFail("Explore did not mount.\n\(app.debugDescription)")
            return app
        }
        return app
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--disable-animations"]
        app.launchEnvironment["PLINX_UI_TEST_SCREEN"] = "youtarrExploreSynthetic"
        app.launchEnvironment["PLINX_YOUTARR_SYNTHETIC_URL"] = baseURL.absoluteString
        app.launchEnvironment["PLINX_YOUTARR_SYNTHETIC_API_KEY"] = apiKey
        return app
    }

    private func selectScenario(_ scenario: String, delayMs: Int = 0) async throws {
        let payload = try JSONSerialization.data(
            withJSONObject: ["scenario": scenario, "delayMs": delayMs]
        )
        var request = URLRequest(url: baseURL.appendingPathComponent("__contract/scenario"))
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    private func contractState() async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent("__contract/state"))
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func waitForArtworkRequests() async throws -> [String] {
        for _ in 0..<50 {
            let state = try await contractState()
            let requests = state["artworkRequests"] as? [String] ?? []
            if requests.contains("channel:8") && requests.contains("video:abcdefghijk") {
                return requests
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        return []
    }

    private func waitForVideoRequest() async throws -> [String: Any] {
        for _ in 0..<50 {
            let state = try await contractState()
            if let request = state["lastVideoRequest"] as? [String: Any] {
                return request
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("The synthetic server did not receive the video request in time.")
        return [:]
    }

}
