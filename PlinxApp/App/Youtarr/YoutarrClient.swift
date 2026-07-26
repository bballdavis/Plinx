import Foundation

enum YoutarrRole: Equatable {
    case view
    case request
    case delete
    case admin
    case unknown(String)
}

extension YoutarrRole: Codable {
    init(from decoder: Decoder) throws {
        switch try String(from: decoder).lowercased() {
        case "view": self = .view
        case "request": self = .request
        case "delete": self = .delete
        case "admin": self = .admin
        default: self = .unknown(try String(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let value: String
        switch self {
        case .view: value = "view"
        case .request: value = "request"
        case .delete: value = "delete"
        case .admin: value = "admin"
        case .unknown(let unknown): value = unknown
        }
        try container.encode(value)
    }
}

enum YoutarrScope: Equatable {
    case catalogRead
    case requestsRead
    case videoRequest
    case channelRequest
    case videoDelete
    case requestsReview
    case unknown(String)
}

extension YoutarrScope: Codable {
    init(from decoder: Decoder) throws {
        let value = try String(from: decoder)
        switch value {
        case "catalog:read": self = .catalogRead
        case "requests:read": self = .requestsRead
        case "video:request": self = .videoRequest
        case "channel:request": self = .channelRequest
        case "video:delete": self = .videoDelete
        case "requests:review": self = .requestsReview
        default: self = .unknown(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let value: String
        switch self {
        case .catalogRead: value = "catalog:read"
        case .requestsRead: value = "requests:read"
        case .videoRequest: value = "video:request"
        case .channelRequest: value = "channel:request"
        case .videoDelete: value = "video:delete"
        case .requestsReview: value = "requests:review"
        case .unknown(let unknown): value = unknown
        }
        try container.encode(value)
    }
}

struct YoutarrCapabilities: Codable, Equatable {
    let apiVersion: String
    let serverVersion: String?
    let role: YoutarrRole
    let scopes: [YoutarrScope]
    let policy: Policy
    let features: Features

    struct Policy: Codable, Equatable {
        let autoApproveVideoRequests: Bool
        let autoApproveChannelRequests: Bool
        let autoApproveDeleteRequests: Bool
        let maxRatingLevel: Int?
        let allowUnrated: Bool
        let allowedMediaTypes: [String]
    }

    struct Features: Codable, Equatable {
        let catalog: Bool
        let requests: Bool
        let channelRequests: Bool
        let deleteRequests: Bool
        let recommendations: Bool
        let authenticatedAssets: Bool
    }
}

protocol YoutarrHTTPSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: YoutarrHTTPSession {}

/// Reject every redirect so the API key is never forwarded beyond the exact
/// parent-approved endpoint, regardless of URLSession's header forwarding
/// behavior.
final class YoutarrRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private enum YoutarrHTTPSessions {
    static let noRedirects: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(
            configuration: configuration,
            delegate: YoutarrRedirectBlocker(),
            delegateQueue: nil
        )
    }()
}

enum YoutarrClientError: LocalizedError, Equatable {
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case serverUnavailable
    case networkUnavailable
    case invalidResponse
    case unsupportedAPIVersion

    var errorDescription: String? {
        switch self {
        case .unauthorized, .forbidden:
            return YoutarrStrings.value("youtarr.error.unauthorized")
        case .notFound:
            return YoutarrStrings.value("youtarr.error.notFound")
        case .rateLimited:
            return YoutarrStrings.value("youtarr.error.rateLimited")
        case .serverUnavailable:
            return YoutarrStrings.value("youtarr.error.serverUnavailable")
        case .networkUnavailable:
            return YoutarrStrings.value("youtarr.error.networkUnavailable")
        case .invalidResponse:
            return YoutarrStrings.value("youtarr.error.invalidResponse")
        case .unsupportedAPIVersion:
            return YoutarrStrings.value("youtarr.error.unsupportedVersion")
        }
    }
}

struct YoutarrClient {
    static let supportedAPIMajorVersion = 1

    private let configuration: YoutarrConfiguration
    private let session: any YoutarrHTTPSession
    private let decoder: JSONDecoder

    init(
        configuration: YoutarrConfiguration,
        session: any YoutarrHTTPSession = YoutarrHTTPSessions.noRedirects,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.configuration = configuration
        self.session = session
        self.decoder = decoder
    }

    func capabilities() async throws -> YoutarrCapabilities {
        var request = URLRequest(url: configuration.endpointURL(path: "capabilities"))
        request.httpMethod = "GET"
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw YoutarrClientError.networkUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw YoutarrClientError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200...299: break
        case 401: throw YoutarrClientError.unauthorized
        case 403: throw YoutarrClientError.forbidden
        case 404: throw YoutarrClientError.notFound
        case 429: throw YoutarrClientError.rateLimited
        case 500...599: throw YoutarrClientError.serverUnavailable
        default: throw YoutarrClientError.invalidResponse
        }

        let capabilities: YoutarrCapabilities
        do {
            capabilities = try decoder.decode(YoutarrCapabilities.self, from: data)
        } catch {
            // Deliberately do not include a response body in diagnostics or UI.
            throw YoutarrClientError.invalidResponse
        }
        guard apiMajorVersion(capabilities.apiVersion) == Self.supportedAPIMajorVersion else {
            throw YoutarrClientError.unsupportedAPIVersion
        }
        return capabilities
    }

    private func apiMajorVersion(_ version: String) -> Int? {
        Int(version.split(separator: ".", maxSplits: 1).first ?? "")
    }
}
