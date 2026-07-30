import SwiftUI
import PlinxCore
import PlinxUI

@MainActor
final class YoutarrExploreViewModel: ObservableObject {
    enum EmptyReason: Equatable {
        case catalog
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
    @Published private(set) var emptyReason: EmptyReason = .catalog
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
                emptyReason = .catalog
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
                emptyReason = catalog.hadSafetyFilteredVideos ? .safetyPolicy : .catalog
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
        hadSafetyFilteredVideos: Bool
    ) {
        var requestedCursor = initialCursor
        var hadSafetyFilteredVideos = false
        repeat {
            let response = try await client.catalogVideos(
                cursor: requestedCursor,
                pageSize: pageSize,
                search: search
            )
            try Task.checkCancellation()
            let candidates = response.data.filter {
                !existingIDs.contains($0.id) && !$0.isDownloaded && !$0.isRequested
            }
            let visible = candidates.filter(safetyPolicy.allows)
            hadSafetyFilteredVideos = hadSafetyFilteredVideos
                || candidates.contains { !safetyPolicy.allows($0) }
            requestedCursor = response.pagination.nextCursor
            if !visible.isEmpty || requestedCursor == nil {
                return (visible, requestedCursor, hadSafetyFilteredVideos)
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
    ) async -> Result<(videos: [YoutarrVideo], nextCursor: String?, hadSafetyFilteredVideos: Bool), Error> {
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

@MainActor
final class YoutarrVideoDetailViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var detail: YoutarrVideoDetail?

    private let youtubeID: String
    private let client: YoutarrClient

    init(video: YoutarrVideo, configuration: YoutarrConfiguration) {
        youtubeID = video.youtubeId
        client = YoutarrClient(configuration: configuration)
    }

    func load() async {
        guard phase == .idle else { return }
        phase = .loading
        do {
            detail = try await client.videoDetail(youtubeID: youtubeID)
            try Task.checkCancellation()
            phase = .ready
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(YoutarrExploreViewModel.message(for: error))
        }
    }

    func retry() async {
        phase = .idle
        await load()
    }
}

struct YoutarrExploreView: View {
    @StateObject private var viewModel: YoutarrExploreViewModel
    @State private var actionTask: Task<Void, Never>?
    @State private var requestTasks: [String: Task<Void, Never>] = [:]
    @State private var selectedVideo: YoutarrVideo?
    @State private var quickActionVideo: YoutarrVideo?
    @AppStorage(PlinxChromeButtonSizePreference.storageKey)
    private var chromeButtonSizeRaw = PlinxChromeButtonSizePreference.defaultValue.rawValue
    private let safetyPolicy: SafetyPolicy

    init(
        configuration: YoutarrConfiguration,
        safetyPolicy: SafetyPolicy,
        client: YoutarrClient? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: YoutarrExploreViewModel(
                configuration: configuration,
                localSafetyPolicy: safetyPolicy,
                client: client
            )
        )
        self.safetyPolicy = safetyPolicy
    }

    var body: some View {
        ZStack {
            PlinxAmbientBackground()
                .accessibilityIdentifier("youtarr.explore.screen")

            VStack(spacing: 0) {
                exploreHeader

                Group {
                    switch viewModel.phase {
                    case .idle, .loading:
                        YoutarrExploreStateView(
                            systemImage: "sparkles.tv",
                            titleKey: "youtarr.explore.loading",
                            showsProgress: true
                        )
                    case .unavailable:
                        YoutarrExploreStateView(
                            systemImage: "lock.shield",
                            titleKey: "youtarr.explore.unavailable",
                            messageKey: "youtarr.explore.unavailable.help"
                        )
                    case .failed(let message):
                        YoutarrExploreStateView(
                            systemImage: "wifi.exclamationmark",
                            titleKey: "youtarr.explore.error",
                            message: message,
                            retry: startReload
                        )
                    case .ready:
                        exploreContent
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedVideo) { video in
            YoutarrVideoDetailSheet(
                video: video,
                configuration: viewModel.configuration,
                requestState: viewModel.requestState(for: video),
                requestAction: {
                    startRequest(video)
                }
            )
            #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .confirmationDialog(
            quickActionVideo?.title ?? "",
            isPresented: Binding(
                get: { quickActionVideo != nil },
                set: { if !$0 { quickActionVideo = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let video = quickActionVideo {
                Button("More Info") {
                    selectedVideo = video
                    quickActionVideo = nil
                }
                quickActionRequestButton(for: video)
                Button("Cancel", role: .cancel) {
                    quickActionVideo = nil
                }
            }
        }
        .task {
            await viewModel.activate()
        }
        .onDisappear {
            viewModel.deactivate()
            actionTask?.cancel()
            actionTask = nil
            requestTasks.values.forEach { $0.cancel() }
            requestTasks = [:]
        }
    }

    private var exploreHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text("youtarr.explore.title", tableName: "Plinx")
                    .font(.title2.bold())

                Spacer(minLength: 0)

                if let capabilities = viewModel.capabilities,
                   YoutarrRequestCapabilityPolicy.canRead(capabilities) {
                    NavigationLink {
                        YoutarrRequestsView(configuration: viewModel.configuration)
                    } label: {
                        PlinxChromeIconLabel(
                            systemImage: "tray.full",
                            sizePreference: chromeButtonSize
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("youtarr.requests.title", tableName: "Plinx"))
                    .accessibilityHint(Text("accessibility.chromeButton.hint", tableName: "Plinx"))
                    .accessibilityIdentifier("youtarr.explore.myRequests")
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                TextField(
                    text: $viewModel.searchText,
                    prompt: Text("youtarr.explore.searchVideos", tableName: "Plinx")
                ) {
                    EmptyView()
                }
                .submitLabel(.search)
                .onSubmit(startReload)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                        startReload()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("common.actions.clear", tableName: "Plinx"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.24), lineWidth: 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var chromeButtonSize: PlinxChromeButtonSizePreference {
        PlinxChromeButtonSizePreference(rawValue: chromeButtonSizeRaw) ?? .defaultValue
    }

    private var exploreContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if !featuredVideos.isEmpty {
                    sectionTitle("youtarr.explore.newToExplore")
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(featuredVideos) { video in
                                videoCard(video, layout: .featured)
                                    .frame(width: 300)
                                    .task {
                                        await viewModel.loadMoreVideosIfNeeded(after: video)
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                } else {
                    catalogState
                }

                if !viewModel.channels.isEmpty {
                    sectionTitle("youtarr.explore.browseChannels")
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(viewModel.channels) { channel in
                                channelLink(channel)
                                    .frame(width: 150)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                } else if let message = viewModel.channelsErrorMessage {
                    sectionError(message, retry: startReload)
                }

                if !remainingVideos.isEmpty {
                    sectionTitle("youtarr.explore.allVideos")
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 170, maximum: 360), spacing: 16)
                        ],
                        spacing: 24
                    ) {
                        ForEach(remainingVideos) { video in
                            videoCard(video, layout: .grid)
                                .task {
                                    await viewModel.loadMoreVideosIfNeeded(after: video)
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if viewModel.isLoadingMoreVideos {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .accessibilityLabel(Text("youtarr.explore.loadingMore", tableName: "Plinx"))
                }
            }
            .padding(.vertical, 16)
        }
        .plinxRefreshable {
            await viewModel.reload()
        }
    }

    private func startReload() {
        actionTask?.cancel()
        actionTask = Task { @MainActor in
            await viewModel.submitSearch()
        }
    }

    @ViewBuilder
    private var catalogState: some View {
        if let message = viewModel.catalogErrorMessage {
            sectionError(message, retry: startReload)
        } else {
            YoutarrExploreStateView(
                systemImage: viewModel.emptyReason == .safetyPolicy ? "checkmark.shield" : "play.slash",
                titleKey: viewModel.emptyReason == .safetyPolicy
                    ? "youtarr.explore.filteredVideos"
                    : "youtarr.explore.emptyVideos",
                messageKey: viewModel.emptyReason == .safetyPolicy
                    ? "youtarr.explore.filteredVideos.help"
                    : "youtarr.explore.emptyVideos.help",
                retry: startReload
            )
            .frame(minHeight: viewModel.channels.isEmpty ? 360 : 240)
        }
    }

    private func sectionError(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
            Button("Try Again", action: retry)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
    }

    private var featuredVideos: [YoutarrVideo] {
        Array(viewModel.videos.prefix(10))
    }

    private var remainingVideos: [YoutarrVideo] {
        Array(viewModel.videos.dropFirst(10))
    }

    private func sectionTitle(_ key: String) -> some View {
        Text(LocalizedStringKey(key), tableName: "Plinx")
            .font(.title2.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
    }

    private func channelLink(_ channel: YoutarrChannel) -> some View {
        NavigationLink {
            if let capabilities = viewModel.capabilities {
                YoutarrChannelView(
                    channel: channel,
                    configuration: viewModel.configuration,
                    capabilities: capabilities,
                    safetyPolicy: safetyPolicy
                )
            }
        } label: {
            YoutarrChannelCard(
                channel: channel,
                configuration: viewModel.configuration
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("youtarr.explore.channel.\(channel.id)")
    }

    private func videoCard(
        _ video: YoutarrVideo,
        layout: YoutarrVideoCard.Layout
    ) -> some View {
        YoutarrVideoCard(
            video: video,
            configuration: viewModel.configuration,
            layout: layout,
            requestState: viewModel.requestState(for: video),
            selectionAction: {
                selectedVideo = video
            },
            longPressAction: {
                quickActionVideo = video
            },
            requestAction: {
                startRequest(video)
            }
        )
    }

    private func startRequest(_ video: YoutarrVideo) {
        guard requestTasks[video.youtubeId] == nil else { return }
        requestTasks[video.youtubeId] = Task { @MainActor in
            await viewModel.requestVideo(video)
            requestTasks[video.youtubeId] = nil
        }
    }

    @ViewBuilder
    private func quickActionRequestButton(for video: YoutarrVideo) -> some View {
        switch viewModel.requestState(for: video) {
        case .eligible:
            Button("Request") { startRequest(video) }
        case .failed:
            Button("Retry Request") { startRequest(video) }
        case .submitting:
            Button("Requesting…") {}
                .disabled(true)
        case .requested:
            Button("Requested") {}
                .disabled(true)
        case .downloaded:
            Button("Already Downloaded") {}
                .disabled(true)
        case .unavailable:
            Button("Request Unavailable") {}
                .disabled(true)
        }
    }
}

/// Owns the root-tab mounting boundary for Explore.
///
/// Keeping an inactive Explore view alive behind `opacity(0)` makes SwiftUI's
/// task cancellation and the app's tab activation lifecycle compete. Mounting
/// the screen only while its tab is active gives every selection one
/// deterministic load task and tears it down when the user leaves.
struct YoutarrExploreTabContent: View {
    let configuration: YoutarrConfiguration
    let safetyPolicy: SafetyPolicy
    let isActive: Bool
    var client: YoutarrClient?

    @ViewBuilder
    var body: some View {
        if isActive {
            YoutarrExploreView(
                configuration: configuration,
                safetyPolicy: safetyPolicy,
                client: client
            )
        } else {
            Color.clear
        }
    }
}

private struct YoutarrChannelView: View {
    let channel: YoutarrChannel
    @StateObject private var viewModel: YoutarrChannelViewModel
    @State private var actionTask: Task<Void, Never>?
    @State private var requestTasks: [String: Task<Void, Never>] = [:]
    @State private var selectedVideo: YoutarrVideo?

    init(
        channel: YoutarrChannel,
        configuration: YoutarrConfiguration,
        capabilities: YoutarrCapabilities,
        safetyPolicy: SafetyPolicy
    ) {
        self.channel = channel
        _viewModel = StateObject(
            wrappedValue: YoutarrChannelViewModel(
                channel: channel,
                configuration: configuration,
                capabilities: capabilities,
                localSafetyPolicy: safetyPolicy
            )
        )
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                YoutarrExploreStateView(
                    systemImage: "play.rectangle.on.rectangle",
                    titleKey: "youtarr.explore.loadingVideos",
                    showsProgress: true
                )
            case .failed(let message):
                YoutarrExploreStateView(
                    systemImage: "wifi.exclamationmark",
                    titleKey: "youtarr.explore.error",
                    message: message,
                    retry: startReload
                )
            case .ready:
                videoGrid
            }
        }
        .navigationTitle(channel.title)
        .youtarrInlineNavigationTitle()
        .searchable(
            text: $viewModel.searchText,
            prompt: Text("youtarr.explore.searchVideos", tableName: "Plinx")
        )
        .onSubmit(of: .search) {
            startReload()
        }
        .task {
            await viewModel.load()
        }
        .sheet(item: $selectedVideo) { video in
            YoutarrVideoDetailSheet(
                video: video,
                configuration: viewModel.configuration,
                requestState: viewModel.requestState(for: video),
                requestAction: {
                    startRequest(video)
                }
            )
            #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .onDisappear {
            actionTask?.cancel()
            actionTask = nil
            requestTasks.values.forEach { $0.cancel() }
            requestTasks = [:]
        }
        .accessibilityIdentifier("youtarr.explore.channelDetail")
    }

    private var videoGrid: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !viewModel.isFullyIndexed {
                    Label {
                        Text("youtarr.explore.partialCatalog", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("youtarr.explore.partialCatalog")
                }

                if viewModel.videos.isEmpty {
                    YoutarrExploreStateView(
                        systemImage: "play.slash",
                        titleKey: "youtarr.explore.emptyVideos",
                        messageKey: "youtarr.explore.emptyVideos.help",
                        retry: startReload
                    )
                    .frame(minHeight: 320)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 230, maximum: 420), spacing: 16)],
                        spacing: 20
                    ) {
                        ForEach(viewModel.videos) { video in
                            YoutarrVideoCard(
                                video: video,
                                configuration: viewModel.configuration,
                                layout: .grid,
                                requestState: viewModel.requestState(for: video),
                                selectionAction: {
                                    selectedVideo = video
                                },
                                longPressAction: {
                                    selectedVideo = video
                                },
                                requestAction: {
                                    startRequest(video)
                                }
                            )
                            .task {
                                await viewModel.loadNextPageIfNeeded(after: video)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if viewModel.isLoadingNextPage {
                    ProgressView()
                        .padding()
                        .accessibilityLabel(Text("youtarr.explore.loadingMore", tableName: "Plinx"))
                }
            }
            .padding(.vertical, 16)
        }
        .plinxRefreshable {
            await viewModel.reload()
        }
    }

    private func startReload() {
        actionTask?.cancel()
        actionTask = Task { @MainActor in
            await viewModel.submitSearch()
        }
    }

    private func startRequest(_ video: YoutarrVideo) {
        guard requestTasks[video.youtubeId] == nil else { return }
        requestTasks[video.youtubeId] = Task { @MainActor in
            await viewModel.requestVideo(video)
            requestTasks[video.youtubeId] = nil
        }
    }
}

private extension View {
    @ViewBuilder
    func youtarrInlineNavigationTitle() -> some View {
#if os(iOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }

    @ViewBuilder
    func youtarrSearchable(text: Binding<String>, prompt: Text) -> some View {
#if os(iOS)
        searchable(
            text: text,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: prompt
        )
#else
        searchable(text: text, prompt: prompt)
#endif
    }
}

private struct YoutarrChannelCard: View {
    let channel: YoutarrChannel
    let configuration: YoutarrConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            YoutarrThumbnailView(
                rawURL: channel.thumbnailUrl,
                configuration: configuration,
                aspectRatio: 1
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(channel.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(channelSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(channel.title), \(channel.videoCount) "
                + YoutarrStrings.value("youtarr.explore.videos")
        )
    }

    private var channelSummary: String {
        var components = [
            "\(channel.videoCount) \(YoutarrStrings.value("youtarr.explore.videos"))"
        ]
        if channel.downloadedCount > 0 {
            components.append(
                "\(channel.downloadedCount) "
                    + YoutarrStrings.value("youtarr.explore.downloaded")
            )
        }
        if let subfolder = channel.subfolder,
           !subfolder.isEmpty,
           subfolder != "##USE_GLOBAL_DEFAULT##" {
            components.append(subfolder)
        }
        return components.joined(separator: " • ")
    }
}

private struct YoutarrVideoCard: View {
    enum Layout {
        case featured
        case grid
    }

    let video: YoutarrVideo
    let configuration: YoutarrConfiguration
    let layout: Layout
    let requestState: YoutarrVideoActionState
    let selectionAction: () -> Void
    let longPressAction: () -> Void
    let requestAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                YoutarrThumbnailView(
                    rawURL: video.thumbnailUrl,
                    configuration: configuration,
                    aspectRatio: 16 / 9
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let duration = video.duration?.displayValue, !duration.isEmpty {
                    Text(duration)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.8), in: Capsule())
                        .padding(7)
                }
            }

            Text(video.title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(height: titleHeight, alignment: .top)

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(video.channelTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let rating = video.rating {
                        YoutarrMetadataBadge(
                            text: rating.displayValue,
                            systemImage: "checkmark.shield"
                        )
                    } else {
                        Color.clear
                            .frame(height: 14)
                            .accessibilityHidden(true)
                    }
                }

                Spacer(minLength: 4)

                YoutarrCompactRequestControl(
                    video: video,
                    state: requestState,
                    action: requestAction
                )
            }
            .frame(height: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .plinxMediaCardInteraction(
            onTap: selectionAction,
            onLongPress: longPressAction
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityElement(children: .contain)
        .accessibilityAction {
            selectionAction()
        }
        .accessibilityIdentifier("youtarr.explore.video.\(video.youtubeId)")
    }

    private var titleHeight: CGFloat {
        switch layout {
        case .featured: 46
        case .grid: 44
        }
    }
}

private struct YoutarrCompactRequestControl: View {
    let video: YoutarrVideo
    let state: YoutarrVideoActionState
    let action: () -> Void

    var body: some View {
        switch state {
        case .eligible:
            actionButton(
                systemImage: "arrow.down.to.line.compact",
                label: YoutarrStrings.value("youtarr.request.action")
            )

        case .submitting:
            compactSurface {
                ProgressView()
                    .controlSize(.small)
            }
            .accessibilityLabel(Text("youtarr.request.submitting", tableName: "Plinx"))
            .accessibilityIdentifier("youtarr.request.submitting.\(video.youtubeId)")

        case .requested(let status):
            compactSurface {
                Image(
                    systemName: status.map {
                        YoutarrRequestPresentation.systemImage(for: $0)
                    } ?? "clock.fill"
                )
            }
            .accessibilityLabel(
                status.map { Text(YoutarrRequestPresentation.label(for: $0)) }
                    ?? Text("youtarr.explore.requested", tableName: "Plinx")
            )
            .accessibilityIdentifier("youtarr.request.status.\(video.youtubeId)")

        case .downloaded:
            compactSurface {
                Image(systemName: "checkmark.circle.fill")
            }
            .accessibilityLabel(Text("youtarr.explore.downloaded", tableName: "Plinx"))

        case .failed:
            actionButton(
                systemImage: "arrow.clockwise",
                label: YoutarrStrings.value("youtarr.request.retry")
            )

        case .unavailable:
            compactSurface {
                Image(systemName: "lock.fill")
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("youtarr.explore.unavailable", tableName: "Plinx"))
        }
    }

    private func actionButton(systemImage: String, label: String) -> some View {
        Button(action: action) {
            compactSurface {
                Image(systemName: systemImage)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("youtarr.request.video.\(video.youtubeId)")
    }

    private func compactSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
            }
    }
}

private struct YoutarrVideoDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: YoutarrVideoDetailViewModel

    let video: YoutarrVideo
    let configuration: YoutarrConfiguration
    let requestState: YoutarrVideoActionState
    let requestAction: () -> Void

    init(
        video: YoutarrVideo,
        configuration: YoutarrConfiguration,
        requestState: YoutarrVideoActionState,
        requestAction: @escaping () -> Void
    ) {
        self.video = video
        self.configuration = configuration
        self.requestState = requestState
        self.requestAction = requestAction
        _viewModel = StateObject(
            wrappedValue: YoutarrVideoDetailViewModel(
                video: video,
                configuration: configuration
            )
        )
    }

    var body: some View {
        ZStack {
            PlinxAmbientBackground()
                .accessibilityIdentifier("youtarr.details.screen")

            VStack(spacing: 0) {
                detailHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        YoutarrThumbnailView(
                            rawURL: viewModel.detail?.thumbnailUrl ?? video.thumbnailUrl,
                            configuration: configuration,
                            aspectRatio: 16 / 9
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        YoutarrWideRequestControl(
                            video: video,
                            state: requestState,
                            action: requestAction
                        )

                        primaryInformation

                        if viewModel.phase == .loading {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("youtarr.details.loading", tableName: "Plinx")
                            }
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                        }

                        if case .failed(let message) = viewModel.phase {
                            YoutarrExploreStateView(
                                systemImage: "wifi.exclamationmark",
                                titleKey: "youtarr.details.error",
                                message: message,
                                retry: retryDetails
                            )
                            .frame(minHeight: 180)
                        }

                        if let detail = viewModel.detail {
                            fullInformation(detail)
                                .accessibilityIdentifier("youtarr.details.loaded")
                        } else if let description = video.description,
                                  !description.isEmpty {
                            descriptionSection(description)
                        }
                    }
                    .frame(maxWidth: 820, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
        .task {
            await viewModel.load()
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 12) {
            Text("youtarr.details.title", tableName: "Plinx")
                .font(.title2.bold())

            Spacer()

            PlinxChromeButton(systemImage: "xmark") {
                dismiss()
            }
            .accessibilityLabel(Text("common.close", tableName: "Plinx"))
            .accessibilityIdentifier("youtarr.details.close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var primaryInformation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.detail?.title ?? video.title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)

            Text(viewModel.detail?.channelTitle ?? video.channelTitle)
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 118), alignment: .leading)],
                alignment: .leading,
                spacing: 10
            ) {
                if let rating = viewModel.detail?.rating ?? video.rating {
                    detailChip(
                        rating.displayValue,
                        systemImage: "checkmark.shield"
                    )
                }
                if let duration = viewModel.detail?.duration ?? video.duration {
                    detailChip(
                        duration.displayValue,
                        systemImage: "clock"
                    )
                }
                if let published = formattedPublishedDate {
                    detailChip(
                        published,
                        systemImage: "calendar"
                    )
                }
                if let views = compactCount(viewModel.detail?.metadata?.viewCount) {
                    detailChip(
                        views + " " + YoutarrStrings.value("youtarr.details.views"),
                        systemImage: "play.rectangle"
                    )
                }
                if let likes = compactCount(viewModel.detail?.metadata?.likeCount) {
                    detailChip(
                        likes + " " + YoutarrStrings.value("youtarr.details.likes"),
                        systemImage: "hand.thumbsup"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func fullInformation(_ detail: YoutarrVideoDetail) -> some View {
        if let description = detail.metadata?.description, !description.isEmpty {
            descriptionSection(description)
        }

        let rows = technicalRows(detail)
        if !rows.isEmpty {
            detailSection(titleKey: "youtarr.details.videoInformation") {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(row.0)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(row.1)
                                .multilineTextAlignment(.trailing)
                        }
                        .font(.callout)
                        .padding(.vertical, 10)

                        if index < rows.count - 1 {
                            Divider()
                                .overlay(Color.white.opacity(0.08))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
            }
        }

        if let tags = detail.metadata?.tags, !tags.isEmpty {
            detailSection(titleKey: "youtarr.details.tags") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags.prefix(16), id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private func descriptionSection(_ description: String) -> some View {
        detailSection(titleKey: "youtarr.details.description") {
            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detailSection<Content: View>(
        titleKey: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(titleKey), tableName: "Plinx")
                .font(.title3.bold())
            content()
        }
    }

    private func detailChip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var formattedPublishedDate: String? {
        let raw = viewModel.detail?.publishedAt ?? video.publishedAt
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: raw) else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func compactCount(_ value: Int?) -> String? {
        value?.formatted(.number.notation(.compactName))
    }

    private func technicalRows(
        _ detail: YoutarrVideoDetail
    ) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let categories = detail.metadata?.categories, !categories.isEmpty {
            rows.append((
                YoutarrStrings.value("youtarr.details.category"),
                categories.joined(separator: ", ")
            ))
        }
        if let availability = detail.metadata?.availability ?? detail.availability,
           !availability.isEmpty {
            rows.append((
                YoutarrStrings.value("youtarr.details.availability"),
                availability.capitalized
            ))
        }
        if let language = detail.metadata?.language, !language.isEmpty {
            rows.append((
                YoutarrStrings.value("youtarr.details.language"),
                language.uppercased()
            ))
        }
        if let resolution = resolutionDescription(detail) {
            rows.append((
                YoutarrStrings.value("youtarr.details.resolution"),
                resolution
            ))
        }
        if let fps = detail.metadata?.fps {
            rows.append((
                YoutarrStrings.value("youtarr.details.frameRate"),
                String(format: "%.0f fps", fps)
            ))
        }
        if let available = detail.metadata?.availableResolutions, !available.isEmpty {
            rows.append((
                YoutarrStrings.value("youtarr.details.availableResolutions"),
                available.sorted().map { "\($0)p" }.joined(separator: ", ")
            ))
        }
        if let followers = compactCount(detail.metadata?.channelFollowerCount) {
            rows.append((
                YoutarrStrings.value("youtarr.details.channelFollowers"),
                followers
            ))
        }
        return rows
    }

    private func resolutionDescription(_ detail: YoutarrVideoDetail) -> String? {
        if let resolution = detail.metadata?.resolution, !resolution.isEmpty {
            return resolution
        }
        if let width = detail.metadata?.width, let height = detail.metadata?.height {
            return "\(width) × \(height)"
        }
        return detail.videoResolution
    }

    private func retryDetails() {
        Task { @MainActor in
            await viewModel.retry()
        }
    }
}

private struct YoutarrWideRequestControl: View {
    let video: YoutarrVideo
    let state: YoutarrVideoActionState
    let action: () -> Void

    var body: some View {
        switch state {
        case .eligible:
            actionButton(
                title: YoutarrStrings.value("youtarr.request.action"),
                systemImage: "arrow.down.to.line.compact"
            )

        case .failed:
            actionButton(
                title: YoutarrStrings.value("youtarr.request.retry"),
                systemImage: "arrow.clockwise"
            )

        case .submitting:
            wideSurface {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("youtarr.request.submitting", tableName: "Plinx")
                }
            }
            .accessibilityIdentifier("youtarr.request.submitting.\(video.youtubeId)")

        case .requested(let status):
            wideSurface {
                Label(
                    status.map { YoutarrRequestPresentation.label(for: $0) }
                        ?? YoutarrStrings.value("youtarr.explore.requested"),
                    systemImage: status.map {
                        YoutarrRequestPresentation.systemImage(for: $0)
                    } ?? "clock.fill"
                )
            }

        case .downloaded:
            wideSurface {
                Label(
                    YoutarrStrings.value("youtarr.explore.downloaded"),
                    systemImage: "checkmark.circle.fill"
                )
            }

        case .unavailable:
            wideSurface {
                Label(
                    YoutarrStrings.value("youtarr.explore.unavailable"),
                    systemImage: "lock.fill"
                )
            }
            .foregroundStyle(.secondary)
        }
    }

    private func actionButton(title: String, systemImage: String) -> some View {
        Button(action: action) {
            wideSurface {
                Label(title, systemImage: systemImage)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("youtarr.details.request.\(video.youtubeId)")
    }

    private func wideSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .font(.headline)
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.38), lineWidth: 1)
            }
    }
}

private struct YoutarrMetadataBadge: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct YoutarrThumbnailView: View {
    let rawURL: String?
    let configuration: YoutarrConfiguration
    let aspectRatio: CGFloat

    var body: some View {
        Group {
            switch YoutarrAssetRequestPolicy.route(
                rawURL: rawURL,
                configuration: configuration
            ) {
            case .authenticated(let request):
                YoutarrAuthenticatedImageView(request: request)
            case .unavailable:
                placeholder
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipped()
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.16)
            Image(systemName: "play.rectangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }
}

private struct YoutarrAuthenticatedImageView: View {
    let request: URLRequest
    @StateObject private var loader = YoutarrAuthenticatedImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.16)
                    if loader.didFail {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
            }
        }
        .task(id: request.url) {
            await loader.load(request)
        }
    }
}

struct YoutarrExploreStateView: View {
    let systemImage: String
    let titleKey: String
    var messageKey: String?
    var message: String?
    var showsProgress = false
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(LocalizedStringKey(titleKey), tableName: "Plinx")
            } icon: {
                Image(systemName: systemImage)
            }
        } description: {
            if let messageKey {
                Text(LocalizedStringKey(messageKey), tableName: "Plinx")
            } else if let message {
                Text(message)
            }
        } actions: {
            if showsProgress {
                ProgressView()
                    .accessibilityLabel(Text(LocalizedStringKey(titleKey), tableName: "Plinx"))
            }
            if let retry {
                PlinxChromeActionButton(
                    titleKey: "youtarr.explore.retry",
                    systemImage: "arrow.clockwise",
                    action: retry
                )
                .accessibilityIdentifier("youtarr.explore.retry")
            }
        }
    }
}
