import Foundation

/// Local-only guardrails for capturing App Store imagery from the curated Plex
/// library. This mode is unavailable in ordinary launches and deliberately
/// blocks every Plex endpoint that can change watch state.
enum ReleaseScreenshotCaptureMode {
    static let launchArgument = "--release-screenshot-capture"
    private static let liveMode = "live"

    static func isActive(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        arguments.contains("--ui-testing")
            && arguments.contains(launchArgument)
            && environment["PLINX_UI_TEST_MODE"] == liveMode
    }

    static func detailRatingKey(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        validatedSelector(environment["PLINX_RELEASE_CAPTURE_DETAIL_RATING_KEY"])
    }

    static func playbackRatingKey(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        validatedSelector(environment["PLINX_RELEASE_CAPTURE_PLAYBACK_RATING_KEY"])
    }

    static func searchQuery(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        validatedSelector(environment["PLINX_RELEASE_CAPTURE_SEARCH_QUERY"])
    }

    static func allowsDetail(
        ratingKey: String,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        !isActive(arguments: arguments, environment: environment)
            || ratingKey == detailRatingKey(environment: environment)
    }

    static func allowsPlayback(
        ratingKey: String,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        !isActive(arguments: arguments, environment: environment)
            || ratingKey == playbackRatingKey(environment: environment)
    }

    static func shouldBlockWatchMutation(
        url: URL,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard isActive(arguments: arguments, environment: environment) else {
            return false
        }
        switch url.path.lowercased() {
        case "/:/timeline", "/:/scrobble", "/:/unscrobble":
            return true
        default:
            return false
        }
    }

    static func installNetworkMutationBlockerIfNeeded() {
        guard isActive() else { return }
        URLProtocol.registerClass(ReleaseScreenshotMutationBlocker.self)
    }

    private static func validatedSelector(_ rawValue: String?) -> String? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.contains("$(") else {
            return nil
        }
        return value
    }
}

/// Intercepts only watch-state writes while release-capture mode is active.
/// Returning a denial response keeps the upstream player fail-closed without
/// requiring a Strimr source change.
private final class ReleaseScreenshotMutationBlocker: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return ReleaseScreenshotCaptureMode.shouldBlockWatchMutation(url: url)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 403,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"error\":\"release capture is read-only\"}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
