import Foundation

protocol YoutarrRequestServing {
    func requests(
        page: Int,
        pageSize: Int,
        status: YoutarrRequestStatus?
    ) async throws -> YoutarrRequestsResponse

    func request(id: String) async throws -> YoutarrRequest

    func requestVideo(
        youtubeID: String,
        channelID: Int,
        idempotencyKey: UUID
    ) async throws -> YoutarrVideoRequestResponse

    func requestChannel(
        channelURL: String,
        idempotencyKey: UUID
    ) async throws -> YoutarrVideoRequestResponse

    func requestVideoDeletion(
        youtubeID: String,
        channelID: Int,
        idempotencyKey: UUID
    ) async throws -> YoutarrVideoRequestResponse
}

extension YoutarrRequestServing {
    func requestChannel(
        channelURL: String,
        idempotencyKey: UUID
    ) async throws -> YoutarrVideoRequestResponse {
        throw YoutarrClientError.invalidResponse
    }

    func requestVideoDeletion(
        youtubeID: String,
        channelID: Int,
        idempotencyKey: UUID
    ) async throws -> YoutarrVideoRequestResponse {
        throw YoutarrClientError.invalidResponse
    }
}

extension YoutarrClient: YoutarrRequestServing {}

protocol YoutarrRequestVideoDetailServing {
    func videoDetail(youtubeID: String) async throws -> YoutarrVideoDetail
}

extension YoutarrClient: YoutarrRequestVideoDetailServing {}

enum YoutarrRequestCapabilityPolicy {
    static func canRead(_ capabilities: YoutarrCapabilities) -> Bool {
        capabilities.features.requests
            && capabilities.scopes.contains(.requestsRead)
    }

    static func canRequestVideos(_ capabilities: YoutarrCapabilities) -> Bool {
        canRead(capabilities)
            && capabilities.scopes.contains(.videoRequest)
            && supportsVideoRequests(capabilities.role)
    }

    static func canRequestChannels(_ capabilities: YoutarrCapabilities) -> Bool {
        canRead(capabilities)
            && capabilities.features.channelRequests
            && capabilities.scopes.contains(.channelRequest)
            && supportsVideoRequests(capabilities.role)
    }

    static func canRequestDeletion(_ capabilities: YoutarrCapabilities) -> Bool {
        canRead(capabilities)
            && capabilities.features.deleteRequests
            && capabilities.scopes.contains(.videoDelete)
            && {
                switch capabilities.role {
                case .delete, .admin: return true
                case .view, .request, .unknown: return false
                }
            }()
    }

    private static func supportsRequests(_ role: YoutarrRole) -> Bool {
        switch role {
        case .view, .request, .delete, .admin:
            return true
        case .unknown:
            return false
        }
    }

    private static func supportsVideoRequests(_ role: YoutarrRole) -> Bool {
        switch role {
        case .request, .delete, .admin:
            return true
        case .view, .unknown:
            return false
        }
    }
}

enum YoutarrRequestPollingPolicy {
    static let intervalNanoseconds: UInt64 = 15_000_000_000

    static func shouldPoll(
        requests: [YoutarrRequest],
        isVisible: Bool
    ) -> Bool {
        isVisible && requests.contains(where: { $0.status.isActive })
    }
}

enum YoutarrVideoActionState: Equatable {
    case eligible
    case unavailable
    case submitting
    case requested(YoutarrRequestStatus?)
    case downloaded
    case failed(String)

    var preventsSubmission: Bool {
        switch self {
        case .eligible, .failed:
            return false
        case .unavailable, .submitting, .requested, .downloaded:
            return true
        }
    }
}
