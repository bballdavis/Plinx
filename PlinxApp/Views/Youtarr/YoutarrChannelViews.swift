import SwiftUI
import PlinxCore
import PlinxUI

struct YoutarrChannelView: View {
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
