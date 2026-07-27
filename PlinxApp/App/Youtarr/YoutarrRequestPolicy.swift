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
}

extension YoutarrClient: YoutarrRequestServing {}

enum YoutarrRequestCapabilityPolicy {
    static func canRead(_ capabilities: YoutarrCapabilities) -> Bool {
        capabilities.features.requests
            && capabilities.scopes.contains(.requestsRead)
            && supportsRequests(capabilities.role)
    }

    static func canRequestVideos(_ capabilities: YoutarrCapabilities) -> Bool {
        canRead(capabilities)
            && capabilities.scopes.contains(.videoRequest)
            && supportsVideoRequests(capabilities.role)
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
