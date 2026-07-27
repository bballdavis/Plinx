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

struct YoutarrPagination: Codable, Equatable, Sendable {
    let page: Int
    let pageSize: Int
    let total: Int
    let totalPages: Int
}

struct YoutarrChannel: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let channelId: String
    let title: String
    let descriptionSummary: String?
    let thumbnailUrl: String?
    let subfolder: String?
    let videoCount: Int
    let downloadedCount: Int
    let lastFetchedAt: String?
}

struct YoutarrChannelsResponse: Codable, Equatable, Sendable {
    let data: [YoutarrChannel]
    let pagination: YoutarrPagination
    let dataSource: String
}

enum YoutarrVideoRating: Codable, Equatable, Sendable {
    case level(Int)
    case label(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let level = try? container.decode(Int.self) {
            self = .level(level)
        } else if let label = try? container.decode(String.self) {
            self = .label(label)
        } else {
            throw DecodingError.typeMismatch(
                YoutarrVideoRating.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected an integer level or text rating")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .level(let level): try container.encode(level)
        case .label(let label): try container.encode(label)
        }
    }

    var displayValue: String {
        switch self {
        case .level(let level): return YoutarrStrings.value("youtarr.explore.rating.level") + " \(level)"
        case .label(let label): return label
        }
    }
}

enum YoutarrVideoDuration: Codable, Equatable, Sendable {
    case seconds(Int)
    case text(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let seconds = try? container.decode(Int.self) {
            self = .seconds(seconds)
        } else if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            throw DecodingError.typeMismatch(
                YoutarrVideoDuration.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected seconds or duration text")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .seconds(let seconds): try container.encode(seconds)
        case .text(let text): try container.encode(text)
        }
    }

    var displayValue: String {
        switch self {
        case .seconds(let value):
            let clamped = max(0, value)
            let hours = clamped / 3_600
            let minutes = (clamped % 3_600) / 60
            let seconds = clamped % 60
            return hours > 0
                ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
                : String(format: "%d:%02d", minutes, seconds)
        case .text(let text):
            return text
        }
    }
}

struct YoutarrVideo: Codable, Equatable, Identifiable, Sendable {
    var id: String { youtubeId }

    let youtubeId: String
    let title: String
    let thumbnailUrl: String?
    let publishedAt: String?
    let duration: YoutarrVideoDuration?
    let description: String?
    let isDownloaded: Bool
    let isRequested: Bool
    let requestStatus: String?
    let rating: YoutarrVideoRating?
    let channelId: String
    let channelTitle: String
    let mediaType: String
}

struct YoutarrVideosResponse: Codable, Equatable, Sendable {
    let data: [YoutarrVideo]
    let pagination: YoutarrPagination
    let dataSource: String
    let isFullyIndexed: Bool
    let lastIndexedAt: String?
    let indexingHint: String?
}

enum YoutarrRequestStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case pending
    case approved
    case processing
    case completed
    case rejected
    case failed
    case cancelled

    var isActive: Bool {
        switch self {
        case .pending, .approved, .processing:
            return true
        case .completed, .rejected, .failed, .cancelled:
            return false
        }
    }
}

struct YoutarrRequestTarget: Codable, Equatable, Sendable {
    let youtubeId: String
    /// Youtarr's numeric channel database identifier, not YouTube's channel ID.
    let channelId: Int
}

enum YoutarrRequestType: String, Codable, Equatable, Sendable {
    case video
}

struct YoutarrRequest: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let type: YoutarrRequestType
    let status: YoutarrRequestStatus
    let target: YoutarrRequestTarget
    let createdAt: String
    let updatedAt: String
    let decidedAt: String?
    let completedAt: String?
    let message: String?
}

struct YoutarrRequestsResponse: Codable, Equatable, Sendable {
    let data: [YoutarrRequest]
    let pagination: YoutarrPagination
}

enum YoutarrVideoRequestOutcome: String, Codable, Equatable, Sendable {
    case created
    case duplicate
    case alreadyDownloaded = "already_downloaded"
}

struct YoutarrVideoRequestResponse: Codable, Equatable, Sendable {
    let outcome: YoutarrVideoRequestOutcome
    let request: YoutarrRequest?
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

enum YoutarrHTTPSessions {
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
    private let encoder: JSONEncoder

    init(
        configuration: YoutarrConfiguration,
        session: any YoutarrHTTPSession = YoutarrHTTPSessions.noRedirects,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.configuration = configuration
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
    }

    func capabilities() async throws -> YoutarrCapabilities {
        let capabilities: YoutarrCapabilities = try await get(path: "capabilities")
        guard apiMajorVersion(capabilities.apiVersion) == Self.supportedAPIMajorVersion else {
            throw YoutarrClientError.unsupportedAPIVersion
        }
        return capabilities
    }

    func channels(
        page: Int = 1,
        pageSize: Int = 30,
        search: String? = nil
    ) async throws -> YoutarrChannelsResponse {
        try await get(
            path: "channels",
            queryItems: paginationQuery(page: page, pageSize: pageSize, search: search)
        )
    }

    func videos(
        channelID: Int,
        page: Int = 1,
        pageSize: Int = 30,
        search: String? = nil
    ) async throws -> YoutarrVideosResponse {
        try await get(
            path: "channels/\(channelID)/videos",
            queryItems: paginationQuery(page: page, pageSize: pageSize, search: search)
        )
    }

    func requests(
        page: Int = 1,
        pageSize: Int = 30,
        status: YoutarrRequestStatus? = nil
    ) async throws -> YoutarrRequestsResponse {
        var queryItems = paginationQuery(page: page, pageSize: pageSize, search: nil)
        if let status {
            queryItems.append(URLQueryItem(name: "status", value: status.rawValue))
        }
        return try await get(path: "requests", queryItems: queryItems)
    }

    func request(id: String) async throws -> YoutarrRequest {
        try await get(path: "requests/\(id)")
    }

    func requestVideo(
        youtubeID: String,
        channelID: Int,
        idempotencyKey: UUID = UUID()
    ) async throws -> YoutarrVideoRequestResponse {
        struct Body: Encodable {
            let youtubeId: String
            let channelId: Int
            let idempotencyKey: String
        }
        return try await send(
            path: "requests/videos",
            method: "POST",
            body: Body(
                youtubeId: youtubeID,
                channelId: channelID,
                idempotencyKey: idempotencyKey.uuidString.lowercased()
            )
        )
    }

    private func get<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        try await send(
            path: path,
            method: "GET",
            queryItems: queryItems,
            body: Optional<String>.none
        )
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Body?
    ) async throws -> Response {
        guard var components = URLComponents(
            url: configuration.endpointURL(path: path),
            resolvingAgainstBaseURL: false
        ) else {
            throw YoutarrClientError.invalidResponse
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw YoutarrClientError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            do {
                request.httpBody = try encoder.encode(body)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } catch {
                throw YoutarrClientError.invalidResponse
            }
        }

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

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            // Deliberately do not include a response body in diagnostics or UI.
            throw YoutarrClientError.invalidResponse
        }
    }

    private func paginationQuery(page: Int, pageSize: Int, search: String?) -> [URLQueryItem] {
        var result = [
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "pageSize", value: String(min(max(1, pageSize), 100))),
        ]
        if let search = search?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
            result.append(URLQueryItem(name: "search", value: search))
        }
        return result
    }

    private func apiMajorVersion(_ version: String) -> Int? {
        Int(version.split(separator: ".", maxSplits: 1).first ?? "")
    }
}
