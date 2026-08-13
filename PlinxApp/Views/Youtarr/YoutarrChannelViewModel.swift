import SwiftUI
import PlinxCore
import PlinxUI

@MainActor
final class YoutarrChannelViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var videos: [YoutarrVideo] = []
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var isFullyIndexed = true
    @Published private(set) var requestStates: [String: YoutarrVideoActionState] = [:]
    @Published var searchText = ""

    let configuration: YoutarrConfiguration
    private let channel: YoutarrChannel
    private let client: YoutarrClient
    private let requestService: any YoutarrRequestServing
    private let safetyPolicy: YoutarrExploreSafetyPolicy
    private let canRequestVideos: Bool
    private var nextCursor: String?
    private var activeSearch = ""
    private var generation = 0
    private var requestGenerations: [String: UUID] = [:]

    init(
        channel: YoutarrChannel,
        configuration: YoutarrConfiguration,
        capabilities: YoutarrCapabilities,
        localSafetyPolicy: SafetyPolicy,
        client: YoutarrClient? = nil,
        requestService: (any YoutarrRequestServing)? = nil
    ) {
        let resolvedClient = client ?? YoutarrClient(configuration: configuration)
        self.channel = channel
        self.configuration = configuration
        self.client = resolvedClient
        self.requestService = requestService ?? resolvedClient
        self.safetyPolicy = YoutarrExploreSafetyPolicy(
            serverPolicy: capabilities.policy,
            localPolicy: localSafetyPolicy
        )
        self.canRequestVideos = YoutarrRequestCapabilityPolicy.canRequestVideos(capabilities)
    }

    func load() async {
        guard phase == .idle else { return }
        await reload()
    }

    func reload() async {
        generation &+= 1
        let operationGeneration = generation
        let requestedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .loading
        videos = []
        requestStates = [:]
        requestGenerations = [:]
        isLoadingNextPage = false
        nextCursor = nil
        activeSearch = requestedSearch
        do {
            try await loadUntilVisibleOrFinished(
                startingAt: nil,
                search: requestedSearch,
                generation: operationGeneration
            )
            guard operationGeneration == generation else { return }
            phase = .ready
        } catch is CancellationError {
            // Navigation cancellation is intentionally silent.
        } catch {
            guard operationGeneration == generation else { return }
            phase = .failed(YoutarrExploreViewModel.message(for: error))
        }
    }

    func submitSearch() async {
        await reload()
    }

    func loadNextPageIfNeeded(after video: YoutarrVideo) async {
        guard video.id == videos.last?.id,
              !isLoadingNextPage,
              let requestedCursor = nextCursor else {
            return
        }
        let operationGeneration = generation
        let requestedSearch = activeSearch
        isLoadingNextPage = true
        defer {
            if operationGeneration == generation {
                isLoadingNextPage = false
            }
        }
        do {
            try await loadUntilVisibleOrFinished(
                startingAt: requestedCursor,
                search: requestedSearch,
                generation: operationGeneration
            )
        } catch is CancellationError {
            // Scrolling away cancels pagination without replacing visible data.
        } catch {
            guard operationGeneration == generation else { return }
            phase = .failed(YoutarrExploreViewModel.message(for: error))
        }
    }

    func requestState(for video: YoutarrVideo) -> YoutarrVideoActionState {
        requestStates[video.youtubeId] ?? serverState(for: video)
    }

    func requestVideo(_ video: YoutarrVideo) async {
        let currentState = requestState(for: video)
        guard !currentState.preventsSubmission,
              canRequestVideos,
              !video.isDownloaded else {
            return
        }

        let operationGeneration = generation
        let requestGeneration = UUID()
        requestGenerations[video.youtubeId] = requestGeneration
        requestStates[video.youtubeId] = .submitting

        do {
            let response = try await requestService.requestVideo(
                youtubeID: video.youtubeId,
                channelID: channel.id,
                idempotencyKey: UUID()
            )
            try Task.checkCancellation()
            guard operationGeneration == generation,
                  requestGenerations[video.youtubeId] == requestGeneration else {
                return
            }

            switch response.outcome {
            case .created, .duplicate:
                let status = response.request?.status
                requestStates[video.youtubeId] = actionState(for: status)
                updateVideo(
                    video.youtubeId,
                    isDownloaded: false,
                    isRequested: true,
                    requestStatus: status?.rawValue
                )
            case .alreadyDownloaded:
                requestStates[video.youtubeId] = .downloaded
                updateVideo(
                    video.youtubeId,
                    isDownloaded: true,
                    isRequested: false,
                    requestStatus: nil
                )
            case .unknown:
                requestStates[video.youtubeId] = .failed(
                    YoutarrStrings.value("youtarr.request.failed")
                )
            }
        } catch is CancellationError {
            guard operationGeneration == generation,
                  requestGenerations[video.youtubeId] == requestGeneration else {
                return
            }
            requestStates[video.youtubeId] = serverState(for: video)
        } catch {
            guard operationGeneration == generation,
                  requestGenerations[video.youtubeId] == requestGeneration else {
                return
            }
            requestStates[video.youtubeId] = .failed(
                YoutarrExploreViewModel.message(for: error)
            )
        }
    }

    private func loadUntilVisibleOrFinished(
        startingAt cursor: String?,
        search: String,
        generation operationGeneration: Int
    ) async throws {
        var requestedCursor = cursor
        var foundVisibleVideo = false
        repeat {
            let response = try await client.videos(
                channelID: channel.id,
                cursor: requestedCursor,
                pageSize: 30,
                search: search
            )
            try Task.checkCancellation()
            guard operationGeneration == generation else { return }
            isFullyIndexed = response.isFullyIndexed
            let visible = response.data.filter(safetyPolicy.allows)
            let existing = Set(videos.map(\.id))
            let newVideos = visible.filter { !existing.contains($0.id) }
            videos.append(contentsOf: newVideos)
            for video in newVideos where requestStates[video.youtubeId] == nil {
                requestStates[video.youtubeId] = serverState(for: video)
            }
            foundVisibleVideo = !visible.isEmpty
            requestedCursor = response.pagination.nextCursor
            nextCursor = requestedCursor
        } while !foundVisibleVideo && requestedCursor != nil
    }

    private func serverState(for video: YoutarrVideo) -> YoutarrVideoActionState {
        if video.isDownloaded {
            return .downloaded
        }
        if video.isRequested {
            return actionState(
                for: video.requestStatus.flatMap(YoutarrRequestStatus.init(rawValue:))
            )
        }
        return canRequestVideos ? .eligible : .unavailable
    }

    private func actionState(
        for status: YoutarrRequestStatus?
    ) -> YoutarrVideoActionState {
        if status == .failed {
            return .failed(YoutarrStrings.value("youtarr.request.failed"))
        }
        return .requested(status)
    }

    private func updateVideo(
        _ youtubeID: String,
        isDownloaded: Bool,
        isRequested: Bool,
        requestStatus: String?
    ) {
        guard let index = videos.firstIndex(where: { $0.youtubeId == youtubeID }) else {
            return
        }
        let video = videos[index]
        videos[index] = YoutarrVideo(
            youtubeId: video.youtubeId,
            title: video.title,
            thumbnailUrl: video.thumbnailUrl,
            publishedAt: video.publishedAt,
            duration: video.duration,
            description: video.description,
            isDownloaded: isDownloaded,
            isRequested: isRequested,
            requestStatus: requestStatus,
            rating: video.rating,
            channelDatabaseId: video.channelDatabaseId,
            channelId: video.channelId,
            channelTitle: video.channelTitle,
            mediaType: video.mediaType
        )
    }
}
