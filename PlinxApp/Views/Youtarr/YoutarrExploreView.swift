import SwiftUI
import PlinxCore
import PlinxUI

struct YoutarrExploreView: View {
    @StateObject private var viewModel: YoutarrExploreViewModel
    @State private var actionTask: Task<Void, Never>?
    @State private var requestTasks: [String: Task<Void, Never>] = [:]
    @State private var selectedVideo: YoutarrVideo?
    @State private var quickActionVideo: YoutarrVideo?
    @AppStorage(PlinxChromeButtonSizePreference.storageKey)
    private var chromeButtonSizeRaw = PlinxChromeButtonSizePreference.defaultValue.rawValue
    private let safetyPolicy: SafetyPolicy
    private let onRequestShellNavigationFocus: () -> Void
    private let contentFocusRequest: Int
    #if os(tvOS)
    @FocusState private var isSearchFocused: Bool
    @State private var contentFocusGeneration = 0
    #endif

    init(
        configuration: YoutarrConfiguration,
        safetyPolicy: SafetyPolicy,
        client: YoutarrClient? = nil,
        onRequestShellNavigationFocus: @escaping () -> Void = {},
        contentFocusRequest: Int = 0
    ) {
        _viewModel = StateObject(
            wrappedValue: YoutarrExploreViewModel(
                configuration: configuration,
                localSafetyPolicy: safetyPolicy,
                client: client
            )
        )
        self.safetyPolicy = safetyPolicy
        self.onRequestShellNavigationFocus = onRequestShellNavigationFocus
        self.contentFocusRequest = contentFocusRequest
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
        #if os(tvOS)
        .onChange(of: contentFocusRequest) { _, _ in
            contentFocusGeneration &+= 1
            let generation = contentFocusGeneration
            isSearchFocused = false
            Task { @MainActor in
                await Task.yield()
                guard generation == contentFocusGeneration else { return }
                isSearchFocused = true
            }
        }
        #endif
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
                #if os(tvOS)
                .focused($isSearchFocused)
                #endif

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
            #if os(tvOS)
            .plinxFocusSurface(
                isSelected: false,
                isFocused: isSearchFocused,
                style: PlinxFocusSurfaceStyle(cornerRadius: 14)
            )
            .onMoveCommand { direction in
                guard direction == .up else { return }
                contentFocusGeneration &+= 1
                onRequestShellNavigationFocus()
            }
            #endif
        }
        .padding(.horizontal, 16)
        #if os(tvOS)
        .padding(.top, PlinxTVShellMetrics.contentClearance + 8)
        #else
        .padding(.top, 8)
        #endif
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
            let emptyPresentation = emptyPresentation(for: viewModel.emptyReason)
            YoutarrExploreStateView(
                systemImage: emptyPresentation.systemImage,
                titleKey: emptyPresentation.titleKey,
                titleAccessibilityIdentifier: emptyPresentation.accessibilityIdentifier,
                messageKey: emptyPresentation.messageKey,
                retry: startReload
            )
            .frame(minHeight: viewModel.channels.isEmpty ? 360 : 240)
        }
    }

    private func emptyPresentation(for reason: YoutarrExploreViewModel.EmptyReason) -> (
        systemImage: String,
        titleKey: String,
        messageKey: String,
        accessibilityIdentifier: String
    ) {
        switch reason {
        case .noApprovedChannels:
            ("person.crop.circle.badge.exclamationmark", "youtarr.explore.noApprovedChannels", "youtarr.explore.noApprovedChannels.help", "youtarr.explore.empty.noApprovedChannels")
        case .noRequestableVideos:
            ("play.slash", "youtarr.explore.emptyVideos", "youtarr.explore.emptyVideos.help", "youtarr.explore.empty.noRequestableVideos")
        case .search:
            ("magnifyingglass", "youtarr.explore.searchEmpty", "youtarr.explore.searchEmpty.help", "youtarr.explore.empty.search")
        case .safetyPolicy:
            ("checkmark.shield", "youtarr.explore.filteredVideos", "youtarr.explore.filteredVideos.help", "youtarr.explore.empty.safetyPolicy")
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
    var onRequestShellNavigationFocus: () -> Void = {}
    var contentFocusRequest: Int = 0

    @ViewBuilder
    var body: some View {
        if isActive {
            YoutarrExploreView(
                configuration: configuration,
                safetyPolicy: safetyPolicy,
                client: client,
                onRequestShellNavigationFocus: onRequestShellNavigationFocus,
                contentFocusRequest: contentFocusRequest
            )
        } else {
            Color.clear
        }
    }
}
