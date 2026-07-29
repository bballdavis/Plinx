import Foundation
import SwiftUI
import PlinxUI

enum YoutarrRequestPresentation {
    static func label(for status: YoutarrRequestStatus) -> String {
        YoutarrStrings.value("youtarr.requests.status.\(status.rawValue)")
    }

    static func systemImage(for status: YoutarrRequestStatus) -> String {
        switch status {
        case .pending: return "clock"
        case .approved: return "checkmark.circle"
        case .processing: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .rejected: return "hand.raised.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    static func tint(for status: YoutarrRequestStatus) -> Color {
        switch status {
        case .pending: return .orange
        case .approved, .completed: return .green
        case .processing: return .blue
        case .rejected, .failed: return .red
        case .cancelled: return .secondary
        }
    }
}

enum YoutarrRequestListFilter: String, CaseIterable, Identifiable {
    case recent
    case outstanding
    case all

    var id: Self { self }

    var title: String {
        YoutarrStrings.value("youtarr.requests.filter.\(rawValue)")
    }
}

enum YoutarrRequestListPolicy {
    static let recentInterval: TimeInterval = 7 * 24 * 60 * 60

    static func presented(
        _ requests: [YoutarrRequest],
        details: [String: YoutarrVideoDetail],
        filter: YoutarrRequestListFilter,
        searchText: String,
        now: Date = Date()
    ) -> [YoutarrRequest] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return requests
            .filter { matchesFilter($0, filter: filter, now: now) }
            .filter { request in
                guard !query.isEmpty else { return true }
                let detail = details[request.target.youtubeId]
                return [
                    request.target.youtubeId,
                    request.status.rawValue,
                    detail?.title,
                    detail?.channelTitle
                ]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
            }
            .sorted { requestDate($0) > requestDate($1) }
    }

    static func sorted(_ requests: [YoutarrRequest]) -> [YoutarrRequest] {
        requests.sorted { requestDate($0) > requestDate($1) }
    }

    static func requestDate(_ request: YoutarrRequest) -> Date {
        parsedDate(request.createdAt) ?? .distantPast
    }

    private static func matchesFilter(
        _ request: YoutarrRequest,
        filter: YoutarrRequestListFilter,
        now: Date
    ) -> Bool {
        switch filter {
        case .outstanding:
            return request.status.isActive
        case .all:
            return true
        case .recent:
            if request.status.isActive { return true }
            let mostRecentStatusChange = [
                request.completedAt,
                request.decidedAt,
                request.updatedAt,
                request.createdAt
            ]
            .compactMap { $0 }
            .compactMap(parsedDate)
            .max() ?? .distantPast
            return mostRecentStatusChange >= now.addingTimeInterval(-recentInterval)
        }
    }

    private static func parsedDate(_ rawValue: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: rawValue) {
            return date
        }
        return ISO8601DateFormatter().date(from: rawValue)
    }
}

@MainActor
final class YoutarrRequestsViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var requests: [YoutarrRequest] = []
    @Published private(set) var videoDetails: [String: YoutarrVideoDetail] = [:]
    @Published private(set) var isLoadingNextPage = false

    private static let pageSize = 100

    private let service: any YoutarrRequestServing
    private let videoDetailService: any YoutarrRequestVideoDetailServing
    private var nextPage = 1
    private var totalPages = 1
    private var generation = 0
    private var isVisible = false
    private var pollingTask: Task<Void, Never>?
    private var detailLoadsInFlight: Set<String> = []

    init(
        configuration: YoutarrConfiguration,
        service: (any YoutarrRequestServing)? = nil,
        videoDetailService: (any YoutarrRequestVideoDetailServing)? = nil
    ) {
        let client = YoutarrClient(configuration: configuration)
        self.service = service ?? client
        self.videoDetailService = videoDetailService ?? client
    }

    func appear() async {
        isVisible = true
        if phase == .idle {
            await reload()
        } else {
            restartPollingIfNeeded()
        }
    }

    func disappear() {
        isVisible = false
        generation &+= 1
        pollingTask?.cancel()
        pollingTask = nil
        isLoadingNextPage = false
    }

    func reload() async {
        generation &+= 1
        let operationGeneration = generation
        pollingTask?.cancel()
        pollingTask = nil
        phase = .loading
        requests = []
        nextPage = 1
        totalPages = 1
        isLoadingNextPage = false

        do {
            let response = try await service.requests(
                page: 1,
                pageSize: Self.pageSize,
                status: nil
            )
            try Task.checkCancellation()
            guard operationGeneration == generation else { return }
            requests = YoutarrRequestListPolicy.sorted(response.data)
            totalPages = boundedTotalPages(response.pagination.totalPages)
            nextPage = 2
            phase = .ready
            restartPollingIfNeeded()
        } catch is CancellationError {
            // Leaving the screen is intentionally silent.
        } catch {
            guard operationGeneration == generation else { return }
            phase = .failed(YoutarrExploreViewModel.message(for: error))
        }
    }

    func loadNextPageIfNeeded(after request: YoutarrRequest) async {
        guard request.id == requests.last?.id,
              !isLoadingNextPage,
              nextPage <= totalPages else {
            return
        }
        let operationGeneration = generation
        let requestedPage = nextPage
        isLoadingNextPage = true
        defer {
            if operationGeneration == generation {
                isLoadingNextPage = false
            }
        }

        do {
            let response = try await service.requests(
                page: requestedPage,
                pageSize: Self.pageSize,
                status: nil
            )
            try Task.checkCancellation()
            guard operationGeneration == generation else { return }
            let existing = Set(requests.map(\.id))
            requests.append(contentsOf: response.data.filter { !existing.contains($0.id) })
            requests = YoutarrRequestListPolicy.sorted(requests)
            totalPages = boundedTotalPages(response.pagination.totalPages)
            nextPage = requestedPage + 1
            restartPollingIfNeeded()
        } catch is CancellationError {
            // Scrolling away cancels pagination without replacing visible data.
        } catch {
            guard operationGeneration == generation else { return }
            phase = .failed(YoutarrExploreViewModel.message(for: error))
        }
    }

    func loadVideoDetailIfNeeded(for request: YoutarrRequest) async {
        let youtubeID = request.target.youtubeId
        guard videoDetails[youtubeID] == nil,
              !detailLoadsInFlight.contains(youtubeID) else {
            return
        }
        let operationGeneration = generation
        detailLoadsInFlight.insert(youtubeID)
        defer {
            detailLoadsInFlight.remove(youtubeID)
        }

        do {
            let detail = try await videoDetailService.videoDetail(youtubeID: youtubeID)
            try Task.checkCancellation()
            guard operationGeneration == generation else { return }
            videoDetails[youtubeID] = detail
        } catch {
            // Keep the safe ID and status fallback if detail enrichment is unavailable.
        }
    }

    func loadVideoDetailsForSearch() async {
        for request in requests {
            guard !Task.isCancelled else { return }
            await loadVideoDetailIfNeeded(for: request)
        }
    }

    private func restartPollingIfNeeded() {
        pollingTask?.cancel()
        pollingTask = nil
        guard YoutarrRequestPollingPolicy.shouldPoll(
            requests: requests,
            isVisible: isVisible
        ) else {
            return
        }

        let operationGeneration = generation
        pollingTask = Task { @MainActor [weak self] in
            while let self,
                  !Task.isCancelled,
                  operationGeneration == self.generation,
                  YoutarrRequestPollingPolicy.shouldPoll(
                    requests: self.requests,
                    isVisible: self.isVisible
                  ) {
                do {
                    try await Task.sleep(
                        nanoseconds: YoutarrRequestPollingPolicy.intervalNanoseconds
                    )
                    try Task.checkCancellation()
                    let response = try await self.service.requests(
                        page: 1,
                        pageSize: Self.pageSize,
                        status: nil
                    )
                    try Task.checkCancellation()
                    guard operationGeneration == self.generation,
                          self.isVisible else {
                        return
                    }
                    self.mergePolledFirstPage(response.data)
                    self.totalPages = self.boundedTotalPages(response.pagination.totalPages)
                } catch is CancellationError {
                    return
                } catch {
                    // Keep visible data and try again on the next bounded interval.
                }
            }
        }
    }

    private func mergePolledFirstPage(_ firstPage: [YoutarrRequest]) {
        let updates = Dictionary(uniqueKeysWithValues: firstPage.map { ($0.id, $0) })
        requests = requests.map { updates[$0.id] ?? $0 }
        let existing = Set(requests.map(\.id))
        requests.insert(contentsOf: firstPage.filter { !existing.contains($0.id) }, at: 0)
        requests = YoutarrRequestListPolicy.sorted(requests)
    }

    private func boundedTotalPages(_ value: Int) -> Int {
        min(max(1, value), 100)
    }
}

struct YoutarrRequestsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: YoutarrRequestsViewModel
    @State private var searchText = ""
    @State private var listFilter = YoutarrRequestListFilter.recent

    private let configuration: YoutarrConfiguration

    init(configuration: YoutarrConfiguration) {
        self.configuration = configuration
        _viewModel = StateObject(
            wrappedValue: YoutarrRequestsViewModel(configuration: configuration)
        )
    }

    var body: some View {
        ZStack {
            PlinxAmbientBackground()
                .accessibilityIdentifier("youtarr.requests.screen")

            VStack(spacing: 0) {
                requestHeader

                Group {
                    switch viewModel.phase {
                    case .idle, .loading:
                        YoutarrExploreStateView(
                            systemImage: "tray.full",
                            titleKey: "youtarr.requests.loading",
                            showsProgress: true
                        )
                    case .failed(let message):
                        YoutarrExploreStateView(
                            systemImage: "wifi.exclamationmark",
                            titleKey: "youtarr.requests.error",
                            message: message,
                            retry: {
                                Task { await viewModel.reload() }
                            }
                        )
                    case .ready:
                        requestList
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.appear()
        }
        .task(id: searchText) {
            guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            await viewModel.loadVideoDetailsForSearch()
        }
        .onDisappear {
            viewModel.disappear()
        }
    }

    private var requestHeader: some View {
        HStack(spacing: 12) {
            PlinxChromeButton(systemImage: "chevron.left") {
                dismiss()
            }
            .accessibilityIdentifier("youtarr.requests.back")

            Text("youtarr.requests.title", tableName: "Plinx")
                .font(.title2.bold())

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var requestList: some View {
        Group {
            if viewModel.requests.isEmpty {
                YoutarrExploreStateView(
                    systemImage: "tray",
                    titleKey: "youtarr.requests.empty",
                    messageKey: "youtarr.requests.empty.help",
                    retry: {
                        Task { await viewModel.reload() }
                    }
                )
            } else {
                VStack(spacing: 0) {
                    requestControls

                    if presentedRequests.isEmpty {
                        YoutarrExploreStateView(
                            systemImage: "line.3.horizontal.decrease.circle",
                            titleKey: "youtarr.requests.noMatches",
                            messageKey: "youtarr.requests.noMatches.help"
                        )
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(presentedRequests) { request in
                                    YoutarrRequestRow(
                                        request: request,
                                        video: viewModel.videoDetails[request.target.youtubeId],
                                        configuration: configuration
                                    )
                                    .task {
                                        await viewModel.loadVideoDetailIfNeeded(for: request)
                                    }
                                    .task {
                                        await viewModel.loadNextPageIfNeeded(after: request)
                                    }
                                }

                                if viewModel.isLoadingNextPage {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .accessibilityLabel(
                                                Text(
                                                    "youtarr.explore.loadingMore",
                                                    tableName: "Plinx"
                                                )
                                            )
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .plinxRefreshable {
            await viewModel.reload()
        }
    }

    private var requestControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                TextField(
                    text: $searchText,
                    prompt: Text("youtarr.requests.search", tableName: "Plinx")
                ) {
                    EmptyView()
                }
                .submitLabel(.search)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("common.actions.clear", tableName: "Plinx"))
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 8) {
                ForEach(YoutarrRequestListFilter.allCases) { filter in
                    Button {
                        listFilter = filter
                    } label: {
                        Text(filter.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(
                                listFilter == filter ? Color.appBackground : Color.secondary
                            )
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(
                                listFilter == filter
                                    ? AnyShapeStyle(Color.accentColor)
                                    : AnyShapeStyle(.ultraThinMaterial),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("youtarr.requests.filter.\(filter.rawValue)")
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private var presentedRequests: [YoutarrRequest] {
        YoutarrRequestListPolicy.presented(
            viewModel.requests,
            details: viewModel.videoDetails,
            filter: listFilter,
            searchText: searchText
        )
    }
}

private struct YoutarrRequestRow: View {
    let request: YoutarrRequest
    let video: YoutarrVideoDetail?
    let configuration: YoutarrConfiguration

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            YoutarrRequestThumbnail(
                rawURL: video?.thumbnailUrl,
                configuration: configuration
            )
            .frame(width: 116, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(video?.title ?? YoutarrStrings.value("youtarr.requests.video"))
                    .font(.headline)
                    .lineLimit(2)

                if let channelTitle = video?.channelTitle, !channelTitle.isEmpty {
                    Text(channelTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(request.target.youtubeId)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                Label(
                    YoutarrRequestPresentation.label(for: request.status),
                    systemImage: YoutarrRequestPresentation.systemImage(for: request.status)
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(YoutarrRequestPresentation.tint(for: request.status))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    YoutarrRequestPresentation.tint(for: request.status).opacity(0.14),
                    in: Capsule()
                )

                Text(requestedDateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            .frame(minWidth: 118, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(video?.title ?? YoutarrStrings.value("youtarr.requests.video")), "
                + YoutarrRequestPresentation.label(for: request.status)
                + ", \(requestedDateLabel)"
        )
        .accessibilityIdentifier("youtarr.requests.item.\(request.id)")
    }

    private var requestedDateLabel: String {
        let prefix = YoutarrStrings.value("youtarr.requests.requested")
        let date = YoutarrRequestListPolicy.requestDate(request)
        guard date != .distantPast else { return prefix }
        return "\(prefix) \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct YoutarrRequestThumbnail: View {
    let rawURL: String?
    let configuration: YoutarrConfiguration

    var body: some View {
        Group {
            switch YoutarrAssetRequestPolicy.route(
                rawURL: rawURL,
                configuration: configuration
            ) {
            case .authenticated(let request):
                YoutarrRequestAuthenticatedImage(request: request)
            case .unavailable:
                placeholder
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.16)
            Image(systemName: "play.rectangle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct YoutarrRequestAuthenticatedImage: View {
    let request: URLRequest
    @StateObject private var loader = YoutarrAuthenticatedImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if loader.didFail {
                ZStack {
                    Color.secondary.opacity(0.16)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            } else {
                ZStack {
                    Color.secondary.opacity(0.16)
                    ProgressView()
                }
            }
        }
        .task(id: request.url) {
            await loader.load(request)
        }
    }
}
