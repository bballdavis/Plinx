import XCTest
import PlinxCore
@testable import Plinx

final class YoutarrRequestTests: XCTestCase {
    func test_decodesExactRequestContractAndEveryStatus() throws {
        for status in YoutarrRequestStatus.allCases {
            let request = try JSONDecoder().decode(
                YoutarrRequest.self,
                from: requestJSON(id: 17, status: status)
            )

            XCTAssertEqual(request.id, requestIdentifier(17))
            XCTAssertEqual(request.type, .video)
            XCTAssertEqual(request.status, status)
            XCTAssertEqual(request.target.youtubeId, "abcdefghijk")
            XCTAssertEqual(request.target.channelId, 42)
            XCTAssertEqual(request.createdAt, "2026-07-26T10:00:00.000Z")
            XCTAssertEqual(request.updatedAt, "2026-07-26T10:01:00.000Z")
            XCTAssertEqual(request.decidedAt, "2026-07-26T10:00:30.000Z")
            XCTAssertEqual(request.completedAt, "2026-07-26T10:01:00.000Z")
            XCTAssertEqual(request.message, "not shown in kid UI")
        }
    }

    func test_decodesUnknownRequestEnumsWithoutTreatingThemAsActiveVideoRequests() throws {
        let request = try JSONDecoder().decode(
            YoutarrRequest.self,
            from: Data(
                """
                {
                  "id": "future-request",
                  "type": "future_type",
                  "status": "future_status",
                  "target": {"youtubeId": null, "channelId": null, "channelUrl": null},
                  "createdAt": "2026-07-31T12:00:00.000Z",
                  "updatedAt": "2026-07-31T12:00:00.000Z"
                }
                """.utf8
            )
        )

        XCTAssertEqual(request.type, .unknown("future_type"))
        XCTAssertEqual(request.status, .unknown("future_status"))
        XCTAssertFalse(request.status.isActive)
        XCTAssertNil(request.videoYoutubeID)
    }

    func test_postVideoRequestUsesExactBodyAPIKeyAndIdempotencyUUID() async throws {
        let idempotencyKey = UUID(uuidString: "7D286F34-D2A5-41B5-973A-1A9B78073080")!
        let session = RequestRecordingSession(
            data: Data(#"{"outcome":"created","request":null}"#.utf8)
        )
        let client = try makeClient(session: session)

        let response = try await client.requestVideo(
            youtubeID: "abcdefghijk",
            channelID: 42,
            idempotencyKey: idempotencyKey
        )

        XCTAssertEqual(response.outcome, .created)
        let request = try XCTUnwrap(session.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/family/external-api/v1/requests/videos")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "top-secret")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(
            Set(object.keys),
            Set(["youtubeId", "channelId", "idempotencyKey"])
        )
        XCTAssertEqual(object["youtubeId"] as? String, "abcdefghijk")
        XCTAssertEqual(object["channelId"] as? Int, 42)
        XCTAssertEqual(
            object["idempotencyKey"] as? String,
            "7d286f34-d2a5-41b5-973a-1a9b78073080"
        )
    }

    func test_requestsEndpointsBoundPaginationAndEncodeStatus() async throws {
        let session = RequestRecordingSession(
            data: Data(
                """
                {
                  "data": [],
                  "pagination": {"page": 1, "pageSize": 100, "total": 0, "totalPages": 0}
                }
                """.utf8
            )
        )
        let client = try makeClient(session: session)

        _ = try await client.requests(page: 0, pageSize: 500, status: .processing)

        let request = try XCTUnwrap(session.requests.first)
        let components = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
        )
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap {
            item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })
        XCTAssertEqual(components.path, "/family/external-api/v1/requests")
        XCTAssertEqual(query, ["page": "1", "pageSize": "100", "status": "processing"])
    }

    func test_requestDetailUsesUUIDRequestIdentifier() async throws {
        let session = RequestRecordingSession(data: requestJSON(id: 81, status: .pending))
        let client = try makeClient(session: session)
        let requestID = requestIdentifier(81)

        let request = try await client.request(id: requestID)

        XCTAssertEqual(request.id, requestID)
        XCTAssertEqual(
            session.requests.first?.url?.path,
            "/family/external-api/v1/requests/\(requestID)"
        )
    }

    func test_capabilityFeaturesAndScopesAreAuthoritativeForVideoRequests() {
        XCTAssertTrue(
            YoutarrRequestCapabilityPolicy.canRequestVideos(
                capabilities(role: .request)
            )
        )
        XCTAssertTrue(
            YoutarrRequestCapabilityPolicy.canRequestVideos(
                capabilities(role: .delete)
            )
        )
        XCTAssertTrue(
            YoutarrRequestCapabilityPolicy.canRequestVideos(
                capabilities(role: .admin)
            )
        )
        XCTAssertTrue(
            YoutarrRequestCapabilityPolicy.canRequestVideos(
                capabilities(role: .view)
            )
        )
        XCTAssertTrue(
            YoutarrRequestCapabilityPolicy.canRequestVideos(
                capabilities(role: .unknown("future"))
            )
        )
        XCTAssertFalse(
            YoutarrRequestCapabilityPolicy.canRequestVideos(
                capabilities(role: .request, featuresRequests: false)
            )
        )
        XCTAssertFalse(
            YoutarrRequestCapabilityPolicy.canRequestVideos(
                capabilities(role: .request, scopes: [.catalogRead, .requestsRead])
            )
        )
    }

    @MainActor
    func test_createdAndDuplicateResponsesUpdateCatalogAfterServerResponse() async throws {
        for outcome in [YoutarrVideoRequestOutcome.created, .duplicate] {
            let service = RequestServiceMock(
                videoResponse: .init(
                    outcome: outcome,
                    request: decodedRequest(id: 7, status: .pending)
                )
            )
            let viewModel = try makeLoadedChannelViewModel(service: service)
            await viewModel.load()
            let video = try XCTUnwrap(viewModel.videos.first)

            await viewModel.requestVideo(video)

            XCTAssertEqual(viewModel.requestState(for: viewModel.videos[0]), .requested(.pending))
            XCTAssertTrue(viewModel.videos[0].isRequested)
            XCTAssertEqual(viewModel.videos[0].requestStatus, "pending")
            XCTAssertEqual(service.videoCalls.first?.youtubeID, "abcdefghijk")
            XCTAssertEqual(service.videoCalls.first?.channelID, 42)
            XCTAssertNotNil(service.videoCalls.first?.idempotencyKey)
        }
    }

    @MainActor
    func test_alreadyDownloadedResponseUpdatesCatalogWithoutInventingRequest() async throws {
        let service = RequestServiceMock(
            videoResponse: .init(outcome: .alreadyDownloaded, request: nil)
        )
        let viewModel = try makeLoadedChannelViewModel(service: service)
        await viewModel.load()
        let video = try XCTUnwrap(viewModel.videos.first)

        await viewModel.requestVideo(video)

        XCTAssertEqual(viewModel.requestState(for: viewModel.videos[0]), .downloaded)
        XCTAssertTrue(viewModel.videos[0].isDownloaded)
        XCTAssertFalse(viewModel.videos[0].isRequested)
    }

    @MainActor
    func test_unknownRequestOutcomeDoesNotMutateCatalogAsSuccess() async throws {
        let service = RequestServiceMock(
            videoResponse: .init(outcome: .unknown("future_outcome"), request: nil)
        )
        let viewModel = try makeLoadedChannelViewModel(service: service)
        await viewModel.load()
        let video = try XCTUnwrap(viewModel.videos.first)

        await viewModel.requestVideo(video)

        XCTAssertEqual(
            viewModel.requestState(for: viewModel.videos[0]),
            .failed(YoutarrStrings.value("youtarr.request.failed"))
        )
        XCTAssertFalse(viewModel.videos[0].isRequested)
        XCTAssertFalse(viewModel.videos[0].isDownloaded)
    }

    @MainActor
    func test_serverFailedResponseAllowsSafeRetryWithoutShowingServerMessage() async throws {
        let service = RequestServiceMock(
            videoResponse: .init(
                outcome: .created,
                request: decodedRequest(id: 10, status: .failed)
            )
        )
        let viewModel = try makeLoadedChannelViewModel(service: service)
        await viewModel.load()
        let video = try XCTUnwrap(viewModel.videos.first)

        await viewModel.requestVideo(video)
        XCTAssertEqual(
            viewModel.requestState(for: viewModel.videos[0]),
            .failed(YoutarrStrings.value("youtarr.request.failed"))
        )

        await viewModel.requestVideo(viewModel.videos[0])
        XCTAssertEqual(service.videoCalls.count, 2)
    }

    @MainActor
    func test_catalogFailedStatusAllowsSafeRetry() async throws {
        let service = RequestServiceMock(
            videoResponse: .init(
                outcome: .duplicate,
                request: decodedRequest(id: 11, status: .processing)
            )
        )
        let viewModel = try makeLoadedChannelViewModel(
            service: service,
            isRequested: true,
            requestStatus: .failed
        )
        await viewModel.load()
        let video = try XCTUnwrap(viewModel.videos.first)

        XCTAssertEqual(
            viewModel.requestState(for: video),
            .failed(YoutarrStrings.value("youtarr.request.failed"))
        )
        await viewModel.requestVideo(video)
        XCTAssertEqual(service.videoCalls.count, 1)
    }

    @MainActor
    func test_duplicateTapIsIgnoredWhileRequestIsInFlight() async throws {
        let service = SuspendedRequestService()
        let viewModel = try makeLoadedChannelViewModel(service: service)
        await viewModel.load()
        let video = try XCTUnwrap(viewModel.videos.first)

        let first = Task { @MainActor in await viewModel.requestVideo(video) }
        await service.waitUntilStarted()
        await viewModel.requestVideo(video)
        XCTAssertEqual(service.callCount, 1)

        service.resolve(
            .init(outcome: .duplicate, request: decodedRequest(id: 8, status: .approved))
        )
        await first.value
        XCTAssertEqual(viewModel.requestState(for: viewModel.videos[0]), .requested(.approved))
    }

    @MainActor
    func test_reloadMakesLateRequestResponseStale() async throws {
        let service = SuspendedRequestService()
        let viewModel = try makeLoadedChannelViewModel(service: service)
        await viewModel.load()
        let video = try XCTUnwrap(viewModel.videos.first)

        let requestTask = Task { @MainActor in await viewModel.requestVideo(video) }
        await service.waitUntilStarted()
        await viewModel.reload()
        service.resolve(
            .init(outcome: .created, request: decodedRequest(id: 9, status: .pending))
        )
        await requestTask.value

        XCTAssertFalse(viewModel.videos[0].isRequested)
        XCTAssertEqual(viewModel.requestState(for: viewModel.videos[0]), .eligible)
    }

    @MainActor
    func test_requestCancellationRestoresServerStateWithoutError() async throws {
        let service = RequestServiceMock(error: CancellationError())
        let viewModel = try makeLoadedChannelViewModel(service: service)
        await viewModel.load()
        let video = try XCTUnwrap(viewModel.videos.first)

        await viewModel.requestVideo(video)

        XCTAssertEqual(viewModel.requestState(for: video), .eligible)
    }

    func test_pollingOnlyRunsWhileVisibleWithActiveStatuses() {
        XCTAssertGreaterThanOrEqual(
            YoutarrRequestPollingPolicy.intervalNanoseconds,
            10_000_000_000
        )
        XCTAssertTrue(
            YoutarrRequestPollingPolicy.shouldPoll(
                requests: [decodedRequest(id: 1, status: .pending)],
                isVisible: true
            )
        )
        XCTAssertTrue(
            YoutarrRequestPollingPolicy.shouldPoll(
                requests: [decodedRequest(id: 1, status: .approved)],
                isVisible: true
            )
        )
        XCTAssertTrue(
            YoutarrRequestPollingPolicy.shouldPoll(
                requests: [decodedRequest(id: 1, status: .processing)],
                isVisible: true
            )
        )
        XCTAssertFalse(
            YoutarrRequestPollingPolicy.shouldPoll(
                requests: [decodedRequest(id: 1, status: .completed)],
                isVisible: true
            )
        )
        XCTAssertFalse(
            YoutarrRequestPollingPolicy.shouldPoll(
                requests: [decodedRequest(id: 1, status: .pending)],
                isVisible: false
            )
        )
    }

    func test_requestPresentationIsNewestFirstAndRecentKeepsOutstandingItems() throws {
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-29T12:00:00Z")
        )
        let oldOutstanding = request(
            id: "old-outstanding",
            youtubeID: "pending00001",
            status: .pending,
            createdAt: "2026-06-01T09:00:00Z",
            updatedAt: "2026-06-01T09:00:00Z"
        )
        let recentRejected = request(
            id: "recent-rejected",
            youtubeID: "rejected001",
            status: .rejected,
            createdAt: "2026-07-28T11:00:00Z",
            updatedAt: "2026-07-28T12:00:00Z"
        )
        let oldRejected = request(
            id: "old-rejected",
            youtubeID: "rejected002",
            status: .rejected,
            createdAt: "2026-06-02T11:00:00Z",
            updatedAt: "2026-06-02T12:00:00Z"
        )

        let presented = YoutarrRequestListPolicy.presented(
            [oldRejected, oldOutstanding, recentRejected],
            details: [:],
            filter: .recent,
            searchText: "",
            now: now
        )

        XCTAssertEqual(presented.map(\.id), ["recent-rejected", "old-outstanding"])
    }

    func test_outstandingFilterIncludesEveryActiveLifecycleStatus() {
        let requests = [
            request(id: "pending", youtubeID: "pending00001", status: .pending),
            request(id: "approved", youtubeID: "approved001", status: .approved),
            request(id: "processing", youtubeID: "process0001", status: .processing),
            request(id: "completed", youtubeID: "complete001", status: .completed)
        ]

        let presented = YoutarrRequestListPolicy.presented(
            requests,
            details: [:],
            filter: .outstanding,
            searchText: ""
        )

        XCTAssertEqual(Set(presented.map(\.id)), Set(["pending", "approved", "processing"]))
    }

    func test_requestSearchMatchesEnrichedVideoTitleAndChannel() throws {
        let science = request(
            id: "science",
            youtubeID: "science0001",
            status: .completed
        )
        let stories = request(
            id: "stories",
            youtubeID: "stories0001",
            status: .completed
        )
        let detail = try JSONDecoder().decode(
            YoutarrVideoDetail.self,
            from: Data(
                """
                {
                  "youtubeId": "science0001",
                  "title": "A Safe Science Experiment",
                  "isDownloaded": true,
                  "isRequested": false,
                  "channelId": "UC-safe",
                  "channelTitle": "Learning Lab",
                  "mediaType": "video"
                }
                """.utf8
            )
        )

        let byTitle = YoutarrRequestListPolicy.presented(
            [stories, science],
            details: ["science0001": detail],
            filter: .all,
            searchText: "science"
        )
        let byChannel = YoutarrRequestListPolicy.presented(
            [stories, science],
            details: ["science0001": detail],
            filter: .all,
            searchText: "learning"
        )

        XCTAssertEqual(byTitle.map(\.id), ["science"])
        XCTAssertEqual(byChannel.map(\.id), ["science"])
    }

    private func makeClient(session: any YoutarrHTTPSession) throws -> YoutarrClient {
        try YoutarrClient(
            configuration: YoutarrConfiguration(
                baseURL: URL(string: "https://family.example/family")!,
                apiKey: "top-secret"
            ),
            session: session
        )
    }

    @MainActor
    private func makeLoadedChannelViewModel(
        service: any YoutarrRequestServing,
        isRequested: Bool = false,
        requestStatus: YoutarrRequestStatus? = nil
    ) throws -> YoutarrChannelViewModel {
        let configuration = try YoutarrConfiguration(
            baseURL: URL(string: "https://family.example/family")!,
            apiKey: "top-secret"
        )
        let session = RequestRecordingSession(
            data: videosJSON(
                isRequested: isRequested,
                requestStatus: requestStatus
            )
        )
        return YoutarrChannelViewModel(
            channel: .init(
                id: 42,
                channelId: "UC-safe",
                title: "Science Club",
                descriptionSummary: nil,
                thumbnailUrl: nil,
                subfolder: nil,
                videoCount: 1,
                downloadedCount: 0,
                lastFetchedAt: nil
            ),
            configuration: configuration,
            capabilities: capabilities(role: .request),
            localSafetyPolicy: .ratingOnly(max: .r, allowUnrated: true),
            client: YoutarrClient(configuration: configuration, session: session),
            requestService: service
        )
    }

    private func capabilities(
        role: YoutarrRole,
        featuresRequests: Bool = true,
        scopes: [YoutarrScope] = [.catalogRead, .requestsRead, .videoRequest]
    ) -> YoutarrCapabilities {
        .init(
            apiVersion: "1",
            serverVersion: "1.77.0",
            role: role,
            scopes: scopes,
            policy: .init(
                autoApproveVideoRequests: false,
                autoApproveChannelRequests: false,
                autoApproveDeleteRequests: false,
                maxRatingLevel: 4,
                allowUnrated: true,
                allowedMediaTypes: ["video"]
            ),
            features: .init(
                catalog: true,
                requests: featuresRequests,
                channelRequests: false,
                deleteRequests: false,
                recommendations: false,
                authenticatedAssets: true
            )
        )
    }

    private func videosJSON(
        isRequested: Bool = false,
        requestStatus: YoutarrRequestStatus? = nil
    ) -> Data {
        let encodedStatus = requestStatus.map { "\"\($0.rawValue)\"" } ?? "null"
        return Data(
            """
            {
              "data": [{
                "youtubeId": "abcdefghijk",
                "title": "Safe experiment",
                "thumbnailUrl": null,
                "publishedAt": null,
                "duration": 60,
                "description": null,
                "isDownloaded": false,
                "isRequested": \(isRequested),
                "requestStatus": \(encodedStatus),
                "rating": 1,
                "channelId": "UC-safe",
                "channelTitle": "Science Club",
                "mediaType": "video"
              }],
              "pagination": {"page": 1, "pageSize": 30, "total": 1, "totalPages": 1},
              "dataSource": "cache",
              "isFullyIndexed": true,
              "lastIndexedAt": null,
              "indexingHint": null
            }
            """.utf8
        )
    }
}

private final class RequestRecordingSession: YoutarrHTTPSession {
    private let data: Data
    private(set) var requests: [URLRequest] = []

    init(data: Data) {
        self.data = data
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return (
            data,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

private final class RequestServiceMock: YoutarrRequestServing {
    struct VideoCall {
        let youtubeID: String
        let channelID: Int
        let idempotencyKey: UUID
    }

    private let videoResponse: YoutarrVideoRequestResponse?
    private let error: Error?
    private(set) var videoCalls: [VideoCall] = []

    init(
        videoResponse: YoutarrVideoRequestResponse? = nil,
        error: Error? = nil
    ) {
        self.videoResponse = videoResponse
        self.error = error
    }

    func requests(
        page: Int,
        pageSize: Int,
        status: YoutarrRequestStatus?
    ) async throws -> YoutarrRequestsResponse {
        .init(
            data: [],
            pagination: .init(page: page, pageSize: pageSize, total: 0, totalPages: 0)
        )
    }

    func request(id: String) async throws -> YoutarrRequest {
        decodedRequest(id: id, status: .pending)
    }

    func requestVideo(
        youtubeID: String,
        channelID: Int,
        idempotencyKey: UUID
    ) async throws -> YoutarrVideoRequestResponse {
        videoCalls.append(
            .init(
                youtubeID: youtubeID,
                channelID: channelID,
                idempotencyKey: idempotencyKey
            )
        )
        if let error { throw error }
        return videoResponse ?? .init(outcome: .created, request: nil)
    }
}

@MainActor
private final class SuspendedRequestService: YoutarrRequestServing {
    private var continuation: CheckedContinuation<YoutarrVideoRequestResponse, Never>?
    private(set) var callCount = 0

    func requests(
        page: Int,
        pageSize: Int,
        status: YoutarrRequestStatus?
    ) async throws -> YoutarrRequestsResponse {
        .init(
            data: [],
            pagination: .init(page: page, pageSize: pageSize, total: 0, totalPages: 0)
        )
    }

    func request(id: String) async throws -> YoutarrRequest {
        decodedRequest(id: id, status: .pending)
    }

    func requestVideo(
        youtubeID: String,
        channelID: Int,
        idempotencyKey: UUID
    ) async throws -> YoutarrVideoRequestResponse {
        callCount += 1
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        while callCount == 0 {
            await Task.yield()
        }
    }

    func resolve(_ response: YoutarrVideoRequestResponse) {
        continuation?.resume(returning: response)
        continuation = nil
    }
}

private func decodedRequest(
    id: Int,
    status: YoutarrRequestStatus
) -> YoutarrRequest {
    decodedRequest(id: requestIdentifier(id), status: status)
}

private func decodedRequest(
    id: String,
    status: YoutarrRequestStatus
) -> YoutarrRequest {
    try! JSONDecoder().decode(
        YoutarrRequest.self,
        from: requestJSON(id: id, status: status)
    )
}

private func requestJSON(
    id: Int,
    status: YoutarrRequestStatus
) -> Data {
    requestJSON(id: requestIdentifier(id), status: status)
}

private func requestJSON(
    id: String,
    status: YoutarrRequestStatus
) -> Data {
    Data(
        """
        {
          "id": "\(id)",
          "type": "video",
          "status": "\(status.rawValue)",
          "target": {"youtubeId": "abcdefghijk", "channelId": 42},
          "createdAt": "2026-07-26T10:00:00.000Z",
          "updatedAt": "2026-07-26T10:01:00.000Z",
          "decidedAt": "2026-07-26T10:00:30.000Z",
          "completedAt": "2026-07-26T10:01:00.000Z",
          "message": "not shown in kid UI"
        }
        """.utf8
    )
}

private func requestIdentifier(_ value: Int) -> String {
    String(format: "00000000-0000-4000-8000-%012d", value)
}

private func request(
    id: String,
    youtubeID: String,
    status: YoutarrRequestStatus,
    createdAt: String = "2026-07-26T10:00:00Z",
    updatedAt: String = "2026-07-26T10:01:00Z"
) -> YoutarrRequest {
    YoutarrRequest(
        id: id,
        type: .video,
        status: status,
        target: .init(youtubeId: youtubeID, channelId: 42, channelUrl: nil),
        createdAt: createdAt,
        updatedAt: updatedAt,
        decidedAt: status.isActive ? nil : updatedAt,
        completedAt: status == .completed ? updatedAt : nil,
        message: nil
    )
}
