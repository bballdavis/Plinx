import SwiftUI
import PlinxCore

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
    @Published var searchText = ""

    let configuration: YoutarrConfiguration
    private let channel: YoutarrChannel
    private let client: YoutarrClient
    private let safetyPolicy: YoutarrExploreSafetyPolicy
    private var nextPage = 1
    private var totalPages = 1
    private var activeSearch = ""
    private var generation = 0

    init(
        channel: YoutarrChannel,
        configuration: YoutarrConfiguration,
        capabilities: YoutarrCapabilities,
        localSafetyPolicy: SafetyPolicy,
        client: YoutarrClient? = nil
    ) {
        self.channel = channel
        self.configuration = configuration
        self.client = client ?? YoutarrClient(configuration: configuration)
        self.safetyPolicy = YoutarrExploreSafetyPolicy(
            serverPolicy: capabilities.policy,
            localPolicy: localSafetyPolicy
        )
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
            videos.append(contentsOf: visible.filter { !existing.contains($0.id) })
            foundVisibleVideo = !visible.isEmpty
            requestedPage += 1
            nextPage = requestedPage
        } while !foundVisibleVideo && requestedPage <= totalPages
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
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
        .refreshable {
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
        .navigationBarTitleDisplayMode(.inline)
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
                                configuration: viewModel.configuration
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
        .refreshable {
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
                } else if video.isRequested {
                    YoutarrMetadataBadge(
                        text: YoutarrStrings.value("youtarr.explore.requested"),
                        systemImage: "clock.fill"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("youtarr.explore.video.\(video.youtubeId)")
    }

    private var accessibilitySummary: String {
        var values = [video.title, video.channelTitle]
        if let rating = video.rating?.displayValue {
            values.append(rating)
        }
        if video.isDownloaded {
            values.append(YoutarrStrings.value("youtarr.explore.downloaded"))
        } else if video.isRequested {
            values.append(YoutarrStrings.value("youtarr.explore.requested"))
        }
        return values.joined(separator: ", ")
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

private struct YoutarrExploreStateView: View {
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
