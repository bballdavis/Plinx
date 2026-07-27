import SwiftUI

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
    @Published private(set) var isLoadingNextPage = false

    private let service: any YoutarrRequestServing
    private var nextPage = 1
    private var totalPages = 1
    private var generation = 0
    private var isVisible = false
    private var pollingTask: Task<Void, Never>?

    init(
        configuration: YoutarrConfiguration,
        service: (any YoutarrRequestServing)? = nil
    ) {
        self.service = service ?? YoutarrClient(configuration: configuration)
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
            let response = try await service.requests(page: 1, pageSize: 30, status: nil)
            try Task.checkCancellation()
            guard operationGeneration == generation else { return }
            requests = response.data
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
                pageSize: 30,
                status: nil
            )
            try Task.checkCancellation()
            guard operationGeneration == generation else { return }
            let existing = Set(requests.map(\.id))
            requests.append(contentsOf: response.data.filter { !existing.contains($0.id) })
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
                        pageSize: 30,
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
    }

    private func boundedTotalPages(_ value: Int) -> Int {
        min(max(1, value), 100)
    }
}

struct YoutarrRequestsView: View {
    @StateObject private var viewModel: YoutarrRequestsViewModel

    init(configuration: YoutarrConfiguration) {
        _viewModel = StateObject(
            wrappedValue: YoutarrRequestsViewModel(configuration: configuration)
        )
    }

    var body: some View {
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
        .navigationTitle(Text("youtarr.requests.title", tableName: "Plinx"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.appear()
        }
        .onDisappear {
            viewModel.disappear()
        }
        .accessibilityIdentifier("youtarr.requests.screen")
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
                List {
                    ForEach(viewModel.requests) { request in
                        YoutarrRequestRow(request: request)
                            .task {
                                await viewModel.loadNextPageIfNeeded(after: request)
                            }
                    }
                    if viewModel.isLoadingNextPage {
                        HStack {
                            Spacer()
                            ProgressView()
                                .accessibilityLabel(
                                    Text("youtarr.explore.loadingMore", tableName: "Plinx")
                                )
                            Spacer()
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .refreshable {
            await viewModel.reload()
        }
    }
}

private struct YoutarrRequestRow: View {
    let request: YoutarrRequest

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: YoutarrRequestPresentation.systemImage(for: request.status))
                .font(.title2)
                .foregroundStyle(request.status.isActive ? .secondary : .primary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("youtarr.requests.video", tableName: "Plinx")
                    .font(.headline)
                Text(YoutarrRequestPresentation.label(for: request.status))
                    .font(.subheadline.weight(.semibold))
                Text(request.target.youtubeId)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(YoutarrStrings.value("youtarr.requests.video")), "
                + YoutarrRequestPresentation.label(for: request.status)
        )
        .accessibilityIdentifier("youtarr.requests.item.\(request.id)")
    }
}
