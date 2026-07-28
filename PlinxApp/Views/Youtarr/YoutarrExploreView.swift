import SwiftUI
import PlinxCore
import PlinxUI

@MainActor
final class YoutarrExploreViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case unavailable
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var channels: [YoutarrChannel] = []
    @Published private(set) var isLoadingNextPage = false
    @Published var searchText = ""

    let configuration: YoutarrConfiguration
    private let client: YoutarrClient
    private(set) var capabilities: YoutarrCapabilities?
    private var nextPage = 1
    private var totalPages = 1
    private var activeSearch = ""
    private var generation = 0

    init(
        configuration: YoutarrConfiguration,
        client: YoutarrClient? = nil
    ) {
        self.configuration = configuration
        self.client = client ?? YoutarrClient(configuration: configuration)
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
        channels = []
        isLoadingNextPage = false
        nextPage = 1
        totalPages = 1
        activeSearch = requestedSearch

        do {
            let capabilities = try await client.capabilities()
            try Task.checkCancellation()
            guard operationGeneration == generation else { return }
            guard YoutarrCatalogCapabilityPolicy.canBrowse(capabilities) else {
                self.capabilities = capabilities
                phase = .unavailable
                return
            }
            self.capabilities = capabilities
            try await loadPage(
                1,
                search: requestedSearch,
                generation: operationGeneration
            )
            guard operationGeneration == generation else { return }
            phase = .ready
        } catch is CancellationError {
            // A dismissed Explore sheet must not flash an error.
        } catch {
            guard operationGeneration == generation else { return }
            phase = .failed(Self.message(for: error))
        }
    }

    func submitSearch() async {
        await reload()
    }

    func loadNextPageIfNeeded(after channel: YoutarrChannel) async {
        guard channel.id == channels.last?.id,
              !isLoadingNextPage,
              nextPage <= totalPages else {
            return
        }
        let operationGeneration = generation
        let requestedPage = nextPage
        let requestedSearch = activeSearch
        isLoadingNextPage = true
        defer {
            if operationGeneration == generation {
                isLoadingNextPage = false
            }
        }
        do {
            try await loadPage(
                requestedPage,
                search: requestedSearch,
                generation: operationGeneration
            )
        } catch is CancellationError {
            // Scrolling away cancels pagination without replacing visible data.
        } catch {
            guard operationGeneration == generation else { return }
            phase = .failed(Self.message(for: error))
        }
    }

    private func loadPage(
        _ page: Int,
        search: String,
        generation operationGeneration: Int
    ) async throws {
        let response = try await client.channels(
            page: page,
            pageSize: 30,
            search: search
        )
        try Task.checkCancellation()
        guard operationGeneration == generation else { return }
        if page == 1 {
            channels = response.data
        } else {
            let existing = Set(channels.map(\.id))
            channels.append(contentsOf: response.data.filter { !existing.contains($0.id) })
        }
        totalPages = max(1, response.pagination.totalPages)
        nextPage = page + 1
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
    private var nextPage = 1
    private var totalPages = 1
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
        nextPage = 1
        totalPages = 1
        activeSearch = requestedSearch
        do {
            try await loadUntilVisibleOrFinished(
                startingAt: 1,
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
              nextPage <= totalPages else {
            return
        }
        let operationGeneration = generation
        let requestedPage = nextPage
        let requestedSearch = activeSearch
        isLoadingNextPage = true
        defer {
            if operationGeneration == generation {
                isLoadingNextPage = false
            }
        }
        do {
            try await loadUntilVisibleOrFinished(
                startingAt: requestedPage,
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
        startingAt page: Int,
        search: String,
        generation operationGeneration: Int
    ) async throws {
        var requestedPage = page
        var foundVisibleVideo = false
        repeat {
            let response = try await client.videos(
                channelID: channel.id,
                page: requestedPage,
                pageSize: 30,
                search: search
            )
            try Task.checkCancellation()
            guard operationGeneration == generation else { return }
            isFullyIndexed = response.isFullyIndexed
            totalPages = max(1, response.pagination.totalPages)
            let visible = response.data.filter(safetyPolicy.allows)
            let existing = Set(videos.map(\.id))
            let newVideos = visible.filter { !existing.contains($0.id) }
            videos.append(contentsOf: newVideos)
            for video in newVideos where requestStates[video.youtubeId] == nil {
                requestStates[video.youtubeId] = serverState(for: video)
            }
            foundVisibleVideo = !visible.isEmpty
            requestedPage += 1
            nextPage = requestedPage
        } while !foundVisibleVideo && requestedPage <= totalPages
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
            channelId: video.channelId,
            channelTitle: video.channelTitle,
            mediaType: video.mediaType
        )
    }
}

struct YoutarrExploreView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: YoutarrExploreViewModel
    @State private var actionTask: Task<Void, Never>?
    private let safetyPolicy: SafetyPolicy

    init(configuration: YoutarrConfiguration, safetyPolicy: SafetyPolicy) {
        _viewModel = StateObject(
            wrappedValue: YoutarrExploreViewModel(configuration: configuration)
        )
        self.safetyPolicy = safetyPolicy
    }

    var body: some View {
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
                channelGrid
            }
        }
        .navigationTitle(Text("youtarr.explore.title", tableName: "Plinx"))
        .youtarrInlineNavigationTitle()
        .toolbar {
            if let capabilities = viewModel.capabilities,
               YoutarrRequestCapabilityPolicy.canRead(capabilities) {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        YoutarrRequestsView(
                            configuration: viewModel.configuration
                        )
                    } label: {
                        Label(
                            YoutarrStrings.value("youtarr.requests.title"),
                            systemImage: "tray.full"
                        )
                    }
                    .accessibilityIdentifier("youtarr.explore.myRequests")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Label(
                        YoutarrStrings.value("youtarr.explore.close"),
                        systemImage: "xmark"
                    )
                }
                .accessibilityIdentifier("youtarr.explore.close")
            }
        }
        .youtarrSearchable(
            text: $viewModel.searchText,
            prompt: Text("youtarr.explore.searchChannels", tableName: "Plinx")
        )
        .onSubmit(of: .search) {
            startReload()
        }
        .task {
            await viewModel.load()
        }
        .onDisappear {
            actionTask?.cancel()
            actionTask = nil
        }
        .accessibilityIdentifier("youtarr.explore.screen")
    }

    private var channelGrid: some View {
        ScrollView {
            if viewModel.channels.isEmpty {
                YoutarrExploreStateView(
                    systemImage: "rectangle.stack",
                    titleKey: "youtarr.explore.emptyChannels",
                    messageKey: "youtarr.explore.emptyChannels.help",
                    retry: startReload
                )
                .frame(minHeight: 360)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180, maximum: 320), spacing: 16)],
                    spacing: 20
                ) {
                    ForEach(viewModel.channels) { channel in
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
                        .task {
                            await viewModel.loadNextPageIfNeeded(after: channel)
                        }
                    }
                }
                .padding(16)

                if viewModel.isLoadingNextPage {
                    ProgressView()
                        .padding()
                        .accessibilityLabel(Text("youtarr.explore.loadingMore", tableName: "Plinx"))
                }
            }
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
}

private struct YoutarrChannelView: View {
    let channel: YoutarrChannel
    @StateObject private var viewModel: YoutarrChannelViewModel
    @State private var actionTask: Task<Void, Never>?
    @State private var requestTasks: [String: Task<Void, Never>] = [:]

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
                                requestState: viewModel.requestState(for: video),
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
        if let subfolder = channel.subfolder, !subfolder.isEmpty {
            components.append(subfolder)
        }
        return components.joined(separator: " • ")
    }
}

private struct YoutarrVideoCard: View {
    let video: YoutarrVideo
    let configuration: YoutarrConfiguration
    let requestState: YoutarrVideoActionState
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

            Text(video.channelTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                if let rating = video.rating {
                    YoutarrMetadataBadge(
                        text: rating.displayValue,
                        systemImage: "checkmark.shield"
                    )
                }
                if video.isDownloaded {
                    YoutarrMetadataBadge(
                        text: YoutarrStrings.value("youtarr.explore.downloaded"),
                        systemImage: "arrow.down.circle.fill"
                    )
                } else if case .failed = requestState {
                    YoutarrMetadataBadge(
                        text: YoutarrStrings.value("youtarr.requests.status.failed"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                } else if video.isRequested {
                    YoutarrMetadataBadge(
                        text: YoutarrStrings.value("youtarr.explore.requested"),
                        systemImage: "clock.fill"
                    )
                }
            }

            requestControl
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("youtarr.explore.video.\(video.youtubeId)")
    }

    @ViewBuilder
    private var requestControl: some View {
        switch requestState {
        case .eligible:
            Button(action: requestAction) {
                Label(
                    YoutarrStrings.value("youtarr.request.action"),
                    systemImage: "plus.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("youtarr.request.video.\(video.youtubeId)")

        case .submitting:
            HStack {
                ProgressView()
                Text("youtarr.request.submitting", tableName: "Plinx")
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("youtarr.request.submitting.\(video.youtubeId)")

        case .requested(let status):
            Label(
                status.map { YoutarrRequestPresentation.label(for: $0) }
                    ?? YoutarrStrings.value("youtarr.explore.requested"),
                systemImage: status.map { YoutarrRequestPresentation.systemImage(for: $0) }
                    ?? "clock.fill"
            )
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("youtarr.request.status.\(video.youtubeId)")

        case .downloaded:
            Label(
                YoutarrStrings.value("youtarr.explore.downloaded"),
                systemImage: "arrow.down.circle.fill"
            )
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: requestAction) {
                    Label(
                        YoutarrStrings.value("youtarr.request.retry"),
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.bordered)
            }

        case .unavailable:
            EmptyView()
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
            case .publicURL(let url):
                YoutarrAuthenticatedImageView(request: URLRequest(url: url))
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
                Button(action: retry) {
                    Text("youtarr.explore.retry", tableName: "Plinx")
                }
                .accessibilityIdentifier("youtarr.explore.retry")
            }
        }
    }
}
