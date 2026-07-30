import XCTest
@testable import Plinx

final class YoutarrFoundationTests: XCTestCase {
    func test_urlPolicyAcceptsHTTPSAndNormalizesExternalAPIPath() throws {
        let base = try YoutarrURLPolicy.normalizedBaseURL(from: "https://example.test/prefix/external-api/v1/")
        let configuration = try YoutarrConfiguration(baseURL: base, apiKey: "secret")

        XCTAssertEqual(base.absoluteString, "https://example.test/prefix")
        XCTAssertEqual(
            configuration.endpointURL(path: "capabilities").absoluteString,
            "https://example.test/prefix/external-api/v1/capabilities"
        )
    }

    func test_urlPolicyAllowsOnlyLocalHTTPAddresses() throws {
        for address in [
            "http://localhost:3000",
            "http://127.0.0.1",
            "http://10.0.0.2",
            "http://172.16.0.1",
            "http://192.168.1.20",
            "http://youtarr.local",
            "http://[fd00::1]",
            "http://[fe80::1]",
        ] {
            XCTAssertNoThrow(try YoutarrURLPolicy.normalizedBaseURL(from: address), address)
        }

        for address in [
            "http://example.com",
            "http://172.32.0.1",
            "ftp://localhost",
            "https://user:pass@example.test",
            "https://example.test/path?query=value",
            "https://example.test?",
            "https://example.test/path#fragment",
            "https://example.test#",
        ] {
            XCTAssertThrowsError(try YoutarrURLPolicy.normalizedBaseURL(from: address), address)
        }
    }

    func test_configurationStoreKeepsExistingKeyForBlankReplacementAndClearsBothStores() throws {
        let suite = "YoutarrFoundationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = MockCredentialStore()
        let store = YoutarrConfigurationStore(defaults: defaults, credentials: credentials)

        _ = try store.save(baseURL: "https://first.example", apiKey: "first-key")
        let updated = try store.save(baseURL: "https://second.example/", apiKey: "")

        XCTAssertEqual(updated.baseURL.absoluteString, "https://second.example/")
        XCTAssertEqual(updated.apiKey, "first-key")
        XCTAssertEqual(try credentials.string(forKey: "plinx.youtarr.apiKey"), "first-key")

        try store.clear()
        XCTAssertNil(store.storedBaseURL)
        XCTAssertNil(try credentials.string(forKey: "plinx.youtarr.apiKey"))
    }

    func test_configurationStoreRequiresKeyForFirstSave() {
        let suite = "YoutarrFoundationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = YoutarrConfigurationStore(defaults: defaults, credentials: MockCredentialStore())

        XCTAssertThrowsError(try store.save(baseURL: "https://example.test", apiKey: "")) { error in
            XCTAssertEqual(error as? YoutarrConfigurationError, .missingAPIKey)
        }
    }

    func test_configurationStoreSavesRetainsDisablesAndClearsAdditionalHeader() throws {
        let suite = "YoutarrFoundationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = MockCredentialStore()
        let store = YoutarrConfigurationStore(defaults: defaults, credentials: credentials)

        let saved = try store.save(
            baseURL: "https://first.example",
            apiKey: "first-key",
            additionalHeaderEnabled: true,
            additionalHeaderName: "X-Proxy-Secret",
            additionalHeaderValue: "proxy-secret"
        )

        XCTAssertEqual(
            saved.additionalHeader,
            try YoutarrAdditionalHeader(name: "X-Proxy-Secret", value: "proxy-secret")
        )
        XCTAssertTrue(store.hasStoredAdditionalHeader())
        XCTAssertEqual(try store.storedAdditionalHeaderName(), "X-Proxy-Secret")
        XCTAssertEqual(try store.load()?.additionalHeader?.value, "proxy-secret")

        let draft = try store.draft(
            baseURL: "https://second.example",
            apiKey: "",
            additionalHeaderEnabled: true,
            additionalHeaderName: "X-Proxy-Secret",
            additionalHeaderValue: ""
        )
        XCTAssertEqual(draft.additionalHeader?.value, "proxy-secret")

        _ = try store.save(
            baseURL: "https://second.example",
            apiKey: "",
            additionalHeaderEnabled: false
        )
        XCTAssertFalse(store.hasStoredAdditionalHeader())
        XCTAssertNil(try store.load()?.additionalHeader)

        _ = try store.save(
            baseURL: "https://third.example",
            apiKey: "",
            additionalHeaderEnabled: true,
            additionalHeaderName: "X-Proxy-Secret",
            additionalHeaderValue: "replacement-secret"
        )
        try store.clear()
        XCTAssertFalse(store.hasStoredAdditionalHeader())
        XCTAssertNil(store.storedBaseURL)
    }

    func test_additionalHeaderValidationRejectsMissingMalformedAndReservedValues() {
        XCTAssertThrowsError(try YoutarrAdditionalHeader(name: "", value: "value")) { error in
            XCTAssertEqual(error as? YoutarrConfigurationError, .missingAdditionalHeader)
        }
        XCTAssertThrowsError(try YoutarrAdditionalHeader(name: "X Header", value: "value")) { error in
            XCTAssertEqual(error as? YoutarrConfigurationError, .invalidAdditionalHeader)
        }
        for reservedName in ["x-api-key", "Accept", "Content-Type", "Host", "Content-Length"] {
            XCTAssertThrowsError(
                try YoutarrAdditionalHeader(name: reservedName, value: "value"),
                reservedName
            ) { error in
                XCTAssertEqual(error as? YoutarrConfigurationError, .invalidAdditionalHeader)
            }
        }
        XCTAssertThrowsError(try YoutarrAdditionalHeader(name: "Authorization", value: "line\r\nbreak")) { error in
            XCTAssertEqual(error as? YoutarrConfigurationError, .invalidAdditionalHeader)
        }
    }

    func test_draftRequiresNewValueWhenSavedAdditionalHeaderNameChanges() throws {
        let suite = "YoutarrFoundationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = YoutarrConfigurationStore(
            defaults: defaults,
            credentials: MockCredentialStore()
        )
        _ = try store.save(
            baseURL: "https://example.test",
            apiKey: "key",
            additionalHeaderEnabled: true,
            additionalHeaderName: "X-First-Secret",
            additionalHeaderValue: "value"
        )

        XCTAssertThrowsError(
            try store.draft(
                baseURL: "https://example.test",
                apiKey: "",
                additionalHeaderEnabled: true,
                additionalHeaderName: "X-Second-Secret",
                additionalHeaderValue: ""
            )
        ) { error in
            XCTAssertEqual(error as? YoutarrConfigurationError, .missingAdditionalHeader)
        }
    }

    func test_draftUsesUnsavedReplacementInputsWithoutPersisting() async throws {
        let suite = "YoutarrFoundationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = MockCredentialStore()
        let store = YoutarrConfigurationStore(defaults: defaults, credentials: credentials)
        _ = try store.save(baseURL: "https://saved.example", apiKey: "saved-key")

        let draft = try store.draft(baseURL: "https://replacement.example", apiKey: "replacement-key")

        XCTAssertEqual(draft.baseURL.absoluteString, "https://replacement.example/")
        XCTAssertEqual(draft.apiKey, "replacement-key")
        XCTAssertEqual(try store.load()?.baseURL.absoluteString, "https://saved.example/")
        XCTAssertEqual(try store.load()?.apiKey, "saved-key")

        let session = MockHTTPSession(statusCode: 200, data: capabilitiesJSON())
        _ = try await YoutarrClient(configuration: draft, session: session).capabilities()
        let request = try XCTUnwrap(session.lastRequest)
        XCTAssertEqual(request.url?.host, "replacement.example")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "replacement-key")
    }

    func test_draftWithBlankKeyRetainsStoredKeyWithoutPersistingNewURL() throws {
        let suite = "YoutarrFoundationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = MockCredentialStore()
        let store = YoutarrConfigurationStore(defaults: defaults, credentials: credentials)
        _ = try store.save(baseURL: "https://saved.example", apiKey: "saved-key")

        let draft = try store.draft(baseURL: "https://candidate.example", apiKey: "")

        XCTAssertEqual(draft.baseURL.absoluteString, "https://candidate.example/")
        XCTAssertEqual(draft.apiKey, "saved-key")
        XCTAssertEqual(store.storedBaseURL, "https://saved.example/")
    }

    func test_clientBuildsCapabilitiesRequestWithOnlyAPIKeyHeader() async throws {
        let session = MockHTTPSession(statusCode: 200, data: capabilitiesJSON())
        let client = try makeClient(session: session)

        _ = try await client.capabilities()

        let request = try XCTUnwrap(session.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://youtarr.example/external-api/v1/capabilities")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "very-secret-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func test_clientAddsConfiguredAdditionalHeaderToAPIRequests() async throws {
        let session = MockHTTPSession(statusCode: 200, data: capabilitiesJSON())
        let configuration = try YoutarrConfiguration(
            baseURL: URL(string: "https://youtarr.example")!,
            apiKey: "very-secret-key",
            additionalHeader: YoutarrAdditionalHeader(
                name: "X-Proxy-Secret",
                value: "proxy-secret"
            )
        )

        _ = try await YoutarrClient(configuration: configuration, session: session)
            .capabilities()

        let request = try XCTUnwrap(session.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "very-secret-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Proxy-Secret"), "proxy-secret")
    }

    func test_clientDecodesUnknownRoleAndScopeSafely() async throws {
        let data = capabilitiesJSON(role: "future-role", scopes: ["catalog:read", "new-scope"])
        let client = try makeClient(session: MockHTTPSession(statusCode: 200, data: data))

        let capabilities = try await client.capabilities()

        XCTAssertEqual(capabilities.role, .unknown("future-role"))
        XCTAssertEqual(capabilities.scopes, [.catalogRead, .unknown("new-scope")])
    }

    func test_clientDecodesYoutarrContractRolesAndScopes() async throws {
        let data = capabilitiesJSON(
            role: "request",
            scopes: ["catalog:read", "requests:read", "video:request", "channel:request", "video:delete", "requests:review"]
        )
        let client = try makeClient(session: MockHTTPSession(statusCode: 200, data: data))

        let capabilities = try await client.capabilities()

        XCTAssertEqual(capabilities.role, .request)
        XCTAssertEqual(capabilities.scopes, [.catalogRead, .requestsRead, .videoRequest, .channelRequest, .videoDelete, .requestsReview])
    }

    func test_youtarrContractRolesDecodeWithoutFallingBackToUnknown() throws {
        let decoder = JSONDecoder()
        let expected: [(String, YoutarrRole)] = [
            ("view", .view), ("request", .request), ("delete", .delete), ("admin", .admin),
        ]

        for (wireValue, role) in expected {
            XCTAssertEqual(try decoder.decode(YoutarrRole.self, from: Data("\"\(wireValue)\"".utf8)), role)
        }
    }

    func test_clientRejectsUnsupportedAPIVersionAndMapsHTTPFailures() async throws {
        let unsupported = try makeClient(session: MockHTTPSession(statusCode: 200, data: capabilitiesJSON(apiVersion: "2.0")))
        await assertClientError(.unsupportedAPIVersion, from: unsupported)

        let statuses: [(Int, YoutarrClientError)] = [
            (401, .unauthorized), (403, .forbidden), (404, .notFound),
            (429, .rateLimited), (500, .serverUnavailable),
        ]
        for (status, expected) in statuses {
            let client = try makeClient(session: MockHTTPSession(statusCode: status, data: Data()))
            await assertClientError(expected, from: client)
        }
    }

    func test_clientMapsTransportFailureWithoutExposingDetails() async throws {
        let client = try makeClient(session: MockHTTPSession(error: URLError(.notConnectedToInternet)))
        await assertClientError(.networkUnavailable, from: client)
    }

    func test_clientPreservesCancellation() async throws {
        let client = try makeClient(session: MockHTTPSession(error: CancellationError()))

        do {
            _ = try await client.capabilities()
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation must not be presented as a network failure.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func test_clientTreatsURLSessionCancelledAsCancellation() async throws {
        let client = try makeClient(session: MockHTTPSession(error: URLError(.cancelled)))

        do {
            _ = try await client.capabilities()
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // URLSession commonly reports task cancellation as NSURLError -999.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func test_clientTaskCancellationCancelsInFlightRequest() async throws {
        let started = expectation(description: "request started")
        let session = CancellationAwareHTTPSession(started: started)
        let client = try makeClient(session: session)
        let task = Task {
            try await client.capabilities()
        }

        await fulfillment(of: [started], timeout: 1)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // A settings-view disappearance cancels this same task boundary.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func test_redirectPolicyRejectsRedirectWithoutForwardingRequest() {
        let redirectRejected = expectation(description: "redirect rejected")
        let delegate = YoutarrRedirectBlocker()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://youtarr.example/external-api/v1/capabilities")!)
        let response = HTTPURLResponse(
            url: task.originalRequest!.url!,
            statusCode: 302,
            httpVersion: nil,
            headerFields: ["Location": "https://redirect.example/capture"]
        )!
        var followedRequest: URLRequest?

        delegate.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: URL(string: "https://redirect.example/capture")!)
        ) {
            followedRequest = $0
            redirectRejected.fulfill()
        }

        wait(for: [redirectRejected], timeout: 1)
        XCTAssertNil(followedRequest)
    }

    private func makeClient(session: any YoutarrHTTPSession) throws -> YoutarrClient {
        let configuration = try YoutarrConfiguration(
            baseURL: URL(string: "https://youtarr.example")!,
            apiKey: "very-secret-key"
        )
        return YoutarrClient(configuration: configuration, session: session)
    }

    private func assertClientError(_ expected: YoutarrClientError, from client: YoutarrClient) async {
        do {
            _ = try await client.capabilities()
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? YoutarrClientError, expected)
        }
    }

    private func capabilitiesJSON(
        apiVersion: String = "1",
        role: String = "view",
        scopes: [String] = ["catalog:read", "requests:read"]
    ) -> Data {
        let object: [String: Any] = [
            "apiVersion": apiVersion,
            "serverVersion": "1.2.3",
            "role": role,
            "scopes": scopes,
            "policy": [
                "autoApproveVideoRequests": false,
                "autoApproveChannelRequests": false,
                "autoApproveDeleteRequests": false,
                "maxRatingLevel": 3,
                "allowUnrated": false,
                "allowedMediaTypes": ["video"],
            ],
            "features": [
                "catalog": true,
                "requests": true,
                "channelRequests": false,
                "deleteRequests": false,
                "recommendations": false,
                "authenticatedAssets": true,
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: object)
    }
}

private final class MockCredentialStore: YoutarrCredentialStoring {
    private var values: [String: String] = [:]

    func string(forKey key: String) throws -> String? { values[key] }
    func setString(_ value: String, forKey key: String) throws { values[key] = value }
    func deleteValue(forKey key: String) throws { values.removeValue(forKey: key) }
}

private final class MockHTTPSession: YoutarrHTTPSession {
    private let statusCode: Int
    private let data: Data
    private let error: Error?
    private(set) var lastRequest: URLRequest?

    init(statusCode: Int = 200, data: Data = Data(), error: Error? = nil) {
        self.statusCode = statusCode
        self.data = data
        self.error = error
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        if let error { throw error }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil
        )!
        return (data, response)
    }
}

private final class CancellationAwareHTTPSession: YoutarrHTTPSession {
    private let started: XCTestExpectation

    init(started: XCTestExpectation) {
        self.started = started
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        started.fulfill()
        try await Task.sleep(nanoseconds: 30_000_000_000)
        throw XCTSkip("The request should have been cancelled before completing")
    }
}
