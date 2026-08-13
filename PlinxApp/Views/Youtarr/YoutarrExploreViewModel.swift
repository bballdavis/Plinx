import SwiftUI
import PlinxCore
import PlinxUI

import SwiftUI
import PlinxCore
import PlinxUI

@MainActor
final class YoutarrExploreViewModel: ObservableObject {
    enum EmptyReason: Equatable {
        case noApprovedChannels
        case noRequestableVideos
        case search
        case safetyPolicy
    }

    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case unavailable
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var channels: [YoutarrChannel] = []
    @Published private(set) var videos: [YoutarrVideo] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingMoreVideos = false
    @Published private(set) var requestStates: [String: YoutarrVideoActionState] = [:]
    @Published private(set) var emptyReason: EmptyReason = .noRequestableVideos
    @Published private(set) var catalogErrorMessage: String?
    @Published private(set) var channelsErrorMessage: String?
    @Published var searchText = ""

    let configuration: YoutarrConfiguration
    private let client: YoutarrClient
    private let requestService: any YoutarrRequestServing
    private let localSafetyPolicy: SafetyPolicy
    private(set) var capabilities: YoutarrCapabilities?
    private var nextVideoCursor: String?
    private var activeSearch = ""
    private var generation = 0
    private var requestGenerations: [String: UUID] = [:]

    init(
        configuration: YoutarrConfiguration,
        localSafetyPolicy: SafetyPolicy,
        client: YoutarrClient? = nil,
        requestService: (any YoutarrRequestServing)? = nil
    ) {
        let resolvedClient = client ?? YoutarrClient(configuration: configuration)
        self.configuration = configuration
        self.localSafetyPolicy = localSafetyPolicy
        self.client = resolvedClient
        self.requestService = requestService ?? resolvedClient
    }

    func load() async {
        guard phase == .idle else { return }
        await reload()
    }

    /// Refreshes the catalog whenever Explore becomes the active root tab.
    ///
    /// Explore is a discovery surface backed by a changing requestable catalog.
    /// Reusing a prior `.ready` result here can strand the screen in an empty
    /// state after Youtarr indexes channels or its policy changes.
    func activate() async {
        await reload()
    }

    func deactivate() {
        generation &+= 1
        isRefreshing = false
        isLoadingMoreVideos = false
        if phase == .loading {
            phase = .idle
        }
    }

    func reload() async {
        generation &+= 1
        let operationGeneration = generation
        let requestedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hadReadyCatalog = phase == .ready
        if hadReadyCatalog {
            isRefreshing = true
        } else {
            phase = .loading
        }
        isLoadingMoreVideos = false
        defer {
            if operationGeneration == generation {
                isRefreshing = false
            }
        }

        do {
            let loadedCapabilities = try await client.capabilities()
            try Task.checkCancellation()
            guard operationGeneration == generation else { return }
            guard YoutarrCatalogCapabilityPolicy.canBrowse(loadedCapabilities) else {
                capabilities = loadedCapabilities
                channels = []
                videos = []
                requestStates = [:]
                emptyReason = .noRequestableVideos
                requestGenerations = [:]
                nextVideoCursor = nil
                activeSearch = requestedSearch
                phase = .unavailable
                return
            }
            let safetyPolicy = YoutarrExploreSafetyPolicy(
                serverPolicy: loadedCapabilities.policy,
                localPolicy: localSafetyPolicy
            )
            async let channelsResult = loadChannels(search: requestedSearch)
            async let catalogResult = loadCatalog(
                startingAt: nil,
                pageSize: 40,
                search: requestedSearch,
                safetyPolicy: safetyPolicy,
                excluding: []
            )
            let (loadedChannels, loadedCatalog) = await (channelsResult, catalogResult)
            guard operationGeneration == generation else { return }
            capabilities = loadedCapabilities
            activeSearch = requestedSearch

            let channelsSucceeded: Bool
            switch loadedChannels {
            case let .success(response):
                channels = response.data
                channelsErrorMessage = nil
                channelsSucceeded = true
            case let .failure(error):
                if !hadReadyCatalog { channels = [] }
                channelsErrorMessage = Self.message(for: error)
                channelsSucceeded = false
            }

            let catalogSucceeded: Bool
            switch loadedCatalog {
            case let .success(catalog):
                videos = YoutarrCatalogPresentation.diversified(catalog.videos)
                emptyReason = Self.emptyReason(
                    search: requestedSearch,
                    channelsTotal: channelsTotal(from: loadedChannels),
                    catalogTotal: catalog.total,
                    hadSafetyFilteredVideos: catalog.hadSafetyFilteredVideos
                )
                nextVideoCursor = catalog.nextCursor
                catalogErrorMessage = nil
                requestStates = [:]
                requestGenerations = [:]
                seedRequestStates(for: videos)
                catalogSucceeded = true
            case let .failure(error):
                if !hadReadyCatalog {
                    videos = []
                    nextVideoCursor = nil
                }
                catalogErrorMessage = Self.message(for: error)
                catalogSucceeded = false
            }

            phase = (catalogSucceeded || channelsSucceeded || hadReadyCatalog)
                ? .ready
                : .failed(catalogErrorMessage ?? channelsErrorMessage ?? Self.message(for: URLError(.cannotLoadFromNetwork)))
        } catch is CancellationError {
            // Switching away from Explore must not flash an error.
            guard operationGeneration == generation else { return }
            phase = hadReadyCatalog ? .ready : .idle
        } catch {
            guard operationGeneration == generation else { return }
            if hadReadyCatalog {
                phase = .ready
            } else {
                phase = .failed(Self.message(for: error))
            }
        }
    }

    func submitSearch() async {
        await reload()
    }

    func loadMoreVideosIfNeeded(after video: YoutarrVideo) async {
        guard video.id == videos.last?.id,
              !isLoadingMoreVideos,
              let requestedCursor = nextVideoCursor else {
            return
        }
        let operationGeneration = generation
        let requestedSearch = activeSearch
        isLoadingMoreVideos = true
        defer {
            if operationGeneration == generation {
                isLoadingMoreVideos = false
            }
        }
        do {
            guard operationGeneration == generation,
                  let capabilities else { return }
            let safetyPolicy = YoutarrExploreSafetyPolicy(
                serverPolicy: capabilities.policy,
                localPolicy: localSafetyPolicy
            )
            let existing = Set(videos.map(\.id))
            let loadedCatalog = try await loadCatalogUntilVisibleOrFinished(
                startingAt: requestedCursor,
                pageSize: 30,
                search: requestedSearch,
                safetyPolicy: safetyPolicy,
                excluding: existing
            )
            try Task.checkCancellation()
            guard operationGeneration == generation else { return }
            videos = YoutarrCatalogPresentation.diversified(
                videos + loadedCatalog.videos
            )
            nextVideoCursor = loadedCatalog.nextCursor
            seedRequestStates(for: loadedCatalog.videos)
        } catch is CancellationError {
            // Scrolling away cancels pagination without replacing visible data.
        } catch {
            guard operationGeneration == generation else { return }
            // Pagination is supplemental. Keep the committed catalog visible
            // when loading a later page fails.
            phase = .ready
        }
    }

    func requestState(for video: YoutarrVideo) -> YoutarrVideoActionState {
        requestStates[video.youtubeId] ?? serverState(for: video)
    }

    func requestVideo(_ video: YoutarrVideo) async {
        guard let channelDatabaseID = video.channelDatabaseId,
              !requestState(for: video).preventsSubmission,
              let capabilities,
              YoutarrRequestCapabilityPolicy.canRequestVideos(capabilities),
              !video.isDownloaded,
              !video.isRequested else {
            return
        }

        let operationGeneration = generation
        let requestGeneration = UUID()
        requestGenerations[video.youtubeId] = requestGeneration
        requestStates[video.youtubeId] = .submitting

        do {
            _ = try await requestService.requestVideo(
                youtubeID: video.youtubeId,
                channelID: channelDatabaseID,
                idempotencyKey: UUID()
            )
            try Task.checkCancellation()
            guard operationGeneration == generation,
                  requestGenerations[video.youtubeId] == requestGeneration else {
                return
            }
            videos.removeAll { $0.youtubeId == video.youtubeId }
            requestStates[video.youtubeId] = nil
            requestGenerations[video.youtubeId] = nil
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
            requestStates[video.youtubeId] = .failed(Self.message(for: error))
        }
    }

    private func seedRequestStates(for videos: [YoutarrVideo]) {
        for video in videos where requestStates[video.youtubeId] == nil {
            requestStates[video.youtubeId] = serverState(for: video)
        }
    }

    private func loadCatalogUntilVisibleOrFinished(
        startingAt initialCursor: String?,
        pageSize: Int,
        search: String,
        safetyPolicy: YoutarrExploreSafetyPolicy,
        excluding existingIDs: Set<String>
    ) async throws -> (
        videos: [YoutarrVideo],
        nextCursor: String?,
        total: Int,
        hadSafetyFilteredVideos: Bool
    ) {
        var requestedCursor = initialCursor
        var hadSafetyFilteredVideos = false
        var total = 0
        repeat {
            let response = try await client.catalogVideos(
                cursor: requestedCursor,
                pageSize: pageSize,
                search: search
            )
            try Task.checkCancellation()
            total = response.pagination.total
            let candidates = response.data.filter {
                !existingIDs.contains($0.id) && !$0.isDownloaded && !$0.isRequested
            }
            let visible = candidates.filter(safetyPolicy.allows)
            hadSafetyFilteredVideos = hadSafetyFilteredVideos
                || candidates.contains { !safetyPolicy.allows($0) }
            requestedCursor = response.pagination.nextCursor
            if !visible.isEmpty || requestedCursor == nil {
                return (visible, requestedCursor, total, hadSafetyFilteredVideos)
            }
        } while true
    }

    private func loadChannels(
        search: String
    ) async -> Result<YoutarrChannelsResponse, Error> {
        do {
            return .success(try await client.channels(page: 1, pageSize: 100, search: search))
        } catch {
            return .failure(error)
        }
    }

    private func loadCatalog(
        startingAt cursor: String?,
        pageSize: Int,
        search: String,
        safetyPolicy: YoutarrExploreSafetyPolicy,
        excluding existingIDs: Set<String>
    ) async -> Result<(videos: [YoutarrVideo], nextCursor: String?, total: Int, hadSafetyFilteredVideos: Bool), Error> {
        do {
            return .success(try await loadCatalogUntilVisibleOrFinished(
                startingAt: cursor,
                pageSize: pageSize,
                search: search,
                safetyPolicy: safetyPolicy,
                excluding: existingIDs
            ))
        } catch {
            return .failure(error)
        }
    }

    private func channelsTotal(
        from result: Result<YoutarrChannelsResponse, Error>
    ) -> Int? {
        guard case let .success(response) = result else { return nil }
        return response.pagination.total
    }

    private static func emptyReason(
        search: String,
        channelsTotal: Int?,
        catalogTotal: Int,
        hadSafetyFilteredVideos: Bool
    ) -> EmptyReason {
        if !search.isEmpty { return .search }
        if catalogTotal > 0 && hadSafetyFilteredVideos { return .safetyPolicy }
        if channelsTotal == 0 { return .noApprovedChannels }
        if catalogTotal == 0 { return .noRequestableVideos }
        return .noRequestableVideos
    }

    private func serverState(for video: YoutarrVideo) -> YoutarrVideoActionState {
        if video.isDownloaded { return .downloaded }
        if video.isRequested {
            return .requested(
                video.requestStatus.flatMap(YoutarrRequestStatus.init(rawValue:))
            )
        }
        guard video.channelDatabaseId != nil,
              let capabilities,
              YoutarrRequestCapabilityPolicy.canRequestVideos(capabilities) else {
            return .unavailable
        }
        return .eligible
    }

    static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? YoutarrStrings.value("youtarr.error.networkUnavailable")
    }
}
