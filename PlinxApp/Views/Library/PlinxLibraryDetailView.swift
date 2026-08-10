import OSLog
import PlinxCore
import PlinxUI
import SwiftUI

/// Plinx-specific library detail screen.
///
/// This view owns all kid-safety, branding, and navigation chrome for the
/// library drill-down. Plinx owns the presentation wrappers while Strimr
/// supplies the library view models and their filtering seams.
struct PlinxLibraryDetailView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Plinx",
        category: "LibraryDetailSafety"
    )

    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.safetyPolicy) private var safetyPolicy
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var mainCoordinator: MainCoordinator
    #if os(tvOS)
    @Environment(MediaFocusModel.self) private var mediaFocusModel
    @EnvironmentObject private var tvFocusCoordinator: PlinxTVFocusCoordinator
    #endif

    let library: Library
    let onSelectMedia: (MediaDisplayItem) -> Void
    var onLongPressMedia: (MediaDisplayItem) -> Void = { _ in }
    var onRequestShellNavigationFocus: () -> Void = {}
    var contentFocusRequest: Int = 0

    @State private var selectedTab: LibraryDetailTab = .recommended
    #if os(tvOS)
    @State private var tvHeroMedia: MediaItem?
    @FocusState private var isBackFocused: Bool
    @FocusState private var focusedLibraryFilterTab: LibraryDetailTab?
    #endif

    // MARK: - Body

    var body: some View {
        Group {
            #if os(tvOS)
            if selectedTab == .playlists {
                selectedTabContent
                    .safeAreaInset(edge: .top, spacing: 0) {
                        tvHeaderContent
                    }
            } else {
                tvSharedLayout
            }
            #else
            selectedTabContent
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(
            \.preferredLandscapeArtworkKind,
            ArtworkSelectionPolicy.preferredLandscapeArtworkKind(for: library)
        )
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onChange(of: settingsManager.interface.displayCollections) { _, displayCollections in
            if !displayCollections, selectedTab == .collections {
                selectedTab = .recommended
            }
        }
        #if os(tvOS)
        .onChange(of: selectedTab) { _, newTab in
            focusedLibraryFilterTab = newTab
            mediaFocusModel.focusedMedia = nil
            tvHeroMedia = nil
        }
        .onAppear {
            tvFocusCoordinator.activate(.libraryDetail)
            focusedLibraryFilterTab = selectedTab
        }
        .onChange(of: contentFocusRequest) { _, _ in
            focusedLibraryFilterTab = availableTabs.contains(selectedTab)
                ? selectedTab
                : availableTabs.first
        }
        .onExitCommand {
            dismiss()
        }
        #endif
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .recommended:
            #if os(tvOS)
            LibraryTVRecommendedView(
                viewModel: makeRecommendedViewModel(),
                heroMedia: $tvHeroMedia,
                onSelectMedia: onSelectMedia
            )
            #else
            PlinxLibraryRecommendedContentView(
                viewModel: makeRecommendedViewModel(),
                onSelectMedia: onSelectMedia,
                onLongPressMedia: onLongPressMedia,
                topContent: scrollingTopContent,
                overrideLayout: { _ in preferredCarouselLayout },
                onViewAllHub: { hub in
                    mainCoordinator.showHubDetail(hub)
                }
            )
            #endif
        case .browse:
            #if os(tvOS)
            LibraryBrowseView(
                viewModel: makeBrowseViewModel(),
                onSelectMedia: onSelectMedia
            )
            #else
            PlinxLibraryBrowseContentView(
                viewModel: makeBrowseViewModel(),
                onSelectMedia: onSelectMedia,
                onLongPressMedia: onLongPressMedia,
                topContent: scrollingTopContent,
                overrideLayout: preferredCarouselLayout,
                showsControls: false
            )
            #endif
        case .collections:
            #if os(tvOS)
            LibraryCollectionsView(
                viewModel: makeCollectionsViewModel(),
                onSelectMedia: onSelectMedia
            )
            #else
            PlinxLibraryCollectionsContentView(
                viewModel: makeCollectionsViewModel(),
                onSelectMedia: onSelectMedia,
                onLongPressMedia: onLongPressMedia,
                topContent: scrollingTopContent
            )
            #endif
        case .playlists:
            EmptyView()
        }
    }

    // MARK: - Top content (scrolls with each tab's list)

    private var scrollingTopContent: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    PlinxChromeButton(systemImage: "chevron.left") {
                        dismiss()
                    }

                    Text(library.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }

                ZStack(alignment: .trailing) {
                    PlinxLibraryTabPicker(tabs: availableTabs, selectedTab: $selectedTab)
                        .frame(height: 76)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.top, 4)
        )
    }

    // MARK: - Tab helpers

    private var availableTabs: [LibraryDetailTab] {
        LibraryDetailTab.allCases.filter { tab in
            switch tab {
            case .playlists:
                // Plinx: playlists surface is hidden — not suitable for the
                // primary kid-facing library tab.
                false
            case .collections:
                settingsManager.interface.displayCollections
            default:
                true
            }
        }
    }

    #if os(tvOS)
    private var tvSharedLayout: some View {
        SharedTvBrowsePageLayout(
            heroMedia: mediaFocusModel.focusedMedia ?? tvHeroMedia,
            showsFilters: true,
            navigationContent: {
                tvContextRow
            },
            filterContent: {
                tvFilterRow
            },
            rowsContent: { scrollProxy in
                tvRowsContent(scrollProxy: scrollProxy)
            }
        )
    }

    @ViewBuilder
    private func tvRowsContent(scrollProxy: ScrollViewProxy) -> some View {
        switch selectedTab {
        case .recommended:
            PlinxLibraryRecommendedRowsView(
                viewModel: makeRecommendedViewModel(),
                heroMedia: $tvHeroMedia,
                usesLandscapeCards: LibraryCardLayoutPolicy.usesLandscapeDetailCards(for: library, surface: .recommended),
                onSelectMedia: onSelectMedia
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 28)
        case .browse:
            PlinxLibraryBrowseRowsView(
                viewModel: makeBrowseViewModel(),
                heroMedia: $tvHeroMedia,
                usesLandscapeCards: LibraryCardLayoutPolicy.usesLandscapeDetailCards(for: library, surface: .browse),
                onSelectMedia: onSelectMedia,
                onJumpToIndex: { index in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollProxy.scrollTo(index, anchor: .top)
                    }
                }
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 28)
        case .collections:
            PlinxLibraryCollectionsRowsView(
                viewModel: makeCollectionsViewModel(),
                heroMedia: $tvHeroMedia,
                usesLandscapeCards: LibraryCardLayoutPolicy.usesLandscapeDetailCards(for: library, surface: .collections),
                onSelectMedia: onSelectMedia,
                onJumpToIndex: { index in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollProxy.scrollTo(index, anchor: .top)
                    }
                }
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 28)
        case .playlists:
            EmptyView()
        }
    }

    private var tvContextRow: some View {
        HStack(spacing: 16) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.bold))
                    .frame(minWidth: 68, minHeight: 64)
            }
            .buttonStyle(TvPillButtonStyle(isSelected: false))
            .focusEffectDisabled()
            .focused($isBackFocused)
            .accessibilityIdentifier("library.detail.back")
            .onMoveCommand { direction in
                switch direction {
                case .up:
                    isBackFocused = false
                    onRequestShellNavigationFocus()
                case .down:
                    focusedLibraryFilterTab = availableTabs.contains(selectedTab)
                        ? selectedTab
                        : availableTabs.first
                default:
                    break
                }
            }

            Text(library.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white.opacity(0.96))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, PlinxTVShellMetrics.contentClearance + 12)
    }

    private var tvFilterRow: some View {
        HStack(spacing: 12) {
            ForEach(availableTabs) { tab in
                tvFilterButton(tab: tab)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func tvFilterButton(tab: LibraryDetailTab) -> some View {
        Button {
            selectedTab = tab
            focusedLibraryFilterTab = tab
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.plinxIconName)
                    .font(.subheadline.weight(.semibold))
                Text(tab.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .focused($focusedLibraryFilterTab, equals: tab)
        .buttonStyle(TvPillButtonStyle(isSelected: selectedTab == tab))
        .focusEffectDisabled()
        .accessibilityIdentifier("library.detail.filter.\(tab.rawValue)")
        .onMoveCommand { direction in
            guard direction == .up else { return }
            focusedLibraryFilterTab = nil
            isBackFocused = true
        }
    }

    private var tvHeaderContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            tvContextRow

            // Library sub-tabs (Recommended / Browse / Collections)
            tvFilterRow
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.72), Color.black.opacity(0.46), Color.black.opacity(0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    #endif

    // MARK: - Layout heuristic

    /// Portrait (poster) for standard movie/TV libraries; landscape (letterbox)
    /// for "none"-agent libraries (YouTube, Home Videos) and clip libraries.
    private var preferredCarouselLayout: MediaCarousel.Layout? {
        LibraryCardLayoutPolicy.prefersLandscape(for: library) ? .landscape : nil
    }

    // MARK: - ViewModel factories (Plinx-side safety injection)

    private func makeRecommendedViewModel() -> LibraryRecommendedViewModel {
        let vm = LibraryRecommendedViewModel(library: library, context: plexApiContext)
        let policy = safetyPolicy
        vm.hubFilter = { hub in filterRecommendedHub(hub, policy: policy) }
        return vm
    }

    private func makeBrowseViewModel() -> LibraryBrowseViewModel {
        let vm = LibraryBrowseViewModel(
            library: library,
            context: plexApiContext,
            settingsManager: settingsManager
        )
        let policy = safetyPolicy
        let libType = library.type
        vm.itemFilter = { item in
            if (libType == .movie || libType == .show), case .collection = item {
                return false
            }
            return PlinxContentAuthorization.isAllowed(item, policy: policy)
        }
        return vm
    }

    private func makeCollectionsViewModel() -> LibraryCollectionsViewModel {
        #if os(tvOS)
        let vm = LibraryCollectionsViewModel(
            library: library,
            context: plexApiContext,
            settingsManager: settingsManager
        )
        let policy = safetyPolicy
        vm.itemFilter = { item in
            PlinxContentAuthorization.isAllowed(item, policy: policy)
        }
        #else
        let vm = LibraryCollectionsViewModel(library: library, context: plexApiContext)
        let policy = safetyPolicy
        vm.itemFilter = { item in
            PlinxContentAuthorization.isAllowed(item, policy: policy)
        }
        #endif
        return vm
    }

    private func filterRecommendedHub(_ hub: Hub, policy: SafetyPolicy) -> Hub? {
        guard let safetyFiltered = PlinxContentAuthorization.filtered(hub, policy: policy) else {
            Self.logger.debug(
                "Drop hub id=\(hub.id, privacy: .public) title=\(hub.title, privacy: .public) reason=safety_filter_empty"
            )
            return nil
        }
        if safetyFiltered.items.count != hub.items.count {
            Self.logger.debug(
                "Filtered hub id=\(hub.id, privacy: .public) title=\(hub.title, privacy: .public) before=\(hub.items.count) after=\(safetyFiltered.items.count)"
            )
        }
        return safetyFiltered
    }
}

#if !os(tvOS)
private struct PlinxLibraryRecommendedContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State var viewModel: LibraryRecommendedViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onLongPressMedia: (MediaDisplayItem) -> Void
    let topContent: AnyView
    let overrideLayout: (Hub) -> MediaCarousel.Layout?
    let onViewAllHub: (Hub) -> Void

    private let landscapeHubIdentifiers = ["inprogress"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                topContent

                ForEach(viewModel.hubs) { hub in
                    if hub.hasItems {
                        MediaHubSection(
                            title: hub.title,
                            onViewAll: hub.canOpenDetail ? { onViewAllHub(hub) } : nil
                        ) {
                            carousel(for: hub)
                        }
                    }
                }

                if viewModel.isLoading, !viewModel.hasContent {
                    PlinxLoadingStateView(
                        role: .content,
                        label: LocalizedStringResource(
                            "library.recommended.loading",
                            table: "Plinx"
                        )
                    )
                        .frame(maxWidth: .infinity)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if !viewModel.hasContent, !viewModel.isLoading {
                    Text("common.empty.nothingToShow")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .task {
            await viewModel.load()
        }
        .onAppear {
            Task { await viewModel.refreshIfNeeded() }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await viewModel.refreshIfNeeded() }
        }
    }

    private func carousel(for hub: Hub) -> some View {
        let resolvedLayout = layout(for: hub)
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: carouselSpacing(for: resolvedLayout)) {
                ForEach(hub.items) { media in
                    recommendedCard(media, layout: resolvedLayout)
                }
            }
            .padding(.horizontal, 2)
        }
        .mouseDragScrolling()
    }

    private func carouselSpacing(for layout: MediaCarousel.Layout) -> CGFloat {
        switch layout {
        case .portrait: 12
        case .landscape: 16
        }
    }

    @ViewBuilder
    private func recommendedCard(_ media: MediaDisplayItem, layout: MediaCarousel.Layout) -> some View {
        switch layout {
        case .portrait:
            PortraitMediaCard(media: media, showsLabels: true) {
                onSelectMedia(media)
            }
            .plinxQuickActionLongPress { onLongPressMedia(media) }
        case .landscape:
            PlinxLibraryLandscapeMediaCard(media: media, showsLabels: true) {
                onSelectMedia(media)
            }
            .plinxQuickActionLongPress { onLongPressMedia(media) }
        }
    }

    private func layout(for hub: Hub) -> MediaCarousel.Layout {
        if let override = overrideLayout(hub) {
            return override
        }
        let identifier = hub.id.lowercased()
        return landscapeHubIdentifiers.contains(where: identifier.contains) ? .landscape : .portrait
    }
}

private struct PlinxLibraryBrowseContentView: View {
    @State var viewModel: LibraryBrowseViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onLongPressMedia: (MediaDisplayItem) -> Void
    let topContent: AnyView
    let overrideLayout: MediaCarousel.Layout?
    let showsControls: Bool

    private var usesLandscapeCards: Bool {
        guard let overrideLayout else { return false }
        if case .landscape = overrideLayout {
            return true
        }
        return false
    }

    private var cardWidth: CGFloat {
        usesLandscapeCards ? 180 : 112
    }

    private var cardHeight: CGFloat? {
        usesLandscapeCards ? cardWidth * 9 / 16 : nil
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth), spacing: 12, alignment: .top)]
    }

    var body: some View {
        @Bindable var controls = viewModel.controls

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topContent

                if showsControls, controls.hasDisplayTypes {
                    LibraryBrowseControlsView(
                        viewModel: controls,
                        showsBackButton: viewModel.canNavigateBack,
                        onNavigateBack: viewModel.navigateBack
                    )
                }

                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(Array(viewModel.browseItems.enumerated()), id: \.element.id) { index, item in
                        browseCard(item)
                            .task {
                                if index == viewModel.browseItems.count - 1 {
                                    await viewModel.loadMore()
                                }
                            }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .overlay {
            if viewModel.isLoading, viewModel.browseItems.isEmpty {
                PlinxLoadingStateView(
                    role: .content,
                    label: LocalizedStringResource(
                        "library.browse.loading",
                        table: "Plinx"
                    )
                )
            } else if let errorMessage = viewModel.errorMessage, viewModel.browseItems.isEmpty {
                ContentUnavailableView(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("common.errors.tryAgainLater")
                )
                .symbolRenderingMode(.multicolor)
            } else if viewModel.browseItems.isEmpty {
                ContentUnavailableView(
                    "library.browse.empty.title",
                    systemImage: "square.grid.2x2.fill",
                    description: Text("library.browse.empty.description")
                )
            }
        }
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func browseCard(_ item: LibraryBrowseItem) -> some View {
        switch item {
        case let .media(media):
            if usesLandscapeCards {
                PlinxLibraryLandscapeMediaCard(media: media, width: cardWidth, showsLabels: true) {
                    onSelectMedia(media)
                }
                .plinxQuickActionLongPress { onLongPressMedia(media) }
            } else {
                PortraitMediaCard(media: media, width: cardWidth, showsLabels: true) {
                    onSelectMedia(media)
                }
                .plinxQuickActionLongPress { onLongPressMedia(media) }
            }
        case let .folder(folder):
            FolderCard(
                title: folder.title,
                height: cardHeight,
                width: cardWidth,
                showsLabels: true
            ) {
                viewModel.enterFolder(folder)
            }
        }
    }
}

private struct PlinxLibraryCollectionsContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State var viewModel: LibraryCollectionsViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onLongPressMedia: (MediaDisplayItem) -> Void
    let topContent: AnyView

    private let cardWidth: CGFloat = 112
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth), spacing: 12, alignment: .top)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topContent

                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(viewModel.items) { media in
                        PortraitMediaCard(media: media, width: cardWidth, showsLabels: true) {
                            onSelectMedia(media)
                        }
                        .plinxQuickActionLongPress { onLongPressMedia(media) }
                        .task {
                            if media == viewModel.items.last {
                                await viewModel.loadMore()
                            }
                        }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .overlay {
            if viewModel.isLoading, viewModel.items.isEmpty {
                PlinxLoadingStateView(
                    role: .content,
                    label: LocalizedStringResource(
                        "library.browse.loading",
                        table: "Plinx"
                    )
                )
            } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                ContentUnavailableView(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("common.errors.tryAgainLater")
                )
                .symbolRenderingMode(.multicolor)
            } else if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "library.browse.empty.title",
                    systemImage: "square.grid.2x2.fill",
                    description: Text("library.browse.empty.description")
                )
            }
        }
        .task {
            await viewModel.load()
        }
        .onAppear {
            Task { await viewModel.refreshIfNeeded() }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await viewModel.refreshIfNeeded() }
        }
    }
}
#endif

/// Plinx's library-detail landscape card. Strimr's `LandscapeMediaCard`
/// always chooses backdrop art; this wrapper honors the library-specific
/// artwork preference so Other Videos displays each item's Plex thumbnail.
private struct PlinxLibraryLandscapeMediaCard: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.preferredLandscapeArtworkKind) private var preferredArtworkKind

    let media: MediaDisplayItem
    let height: CGFloat?
    let width: CGFloat?
    let showsLabels: Bool
    let onTap: () -> Void

    private let aspectRatio: CGFloat = 16 / 9

    init(
        media: MediaDisplayItem,
        height: CGFloat? = nil,
        width: CGFloat? = nil,
        showsLabels: Bool,
        onTap: @escaping () -> Void
    ) {
        self.media = media
        self.height = height
        self.width = width
        self.showsLabels = showsLabels
        self.onTap = onTap
    }

    private var defaultHeight: CGFloat {
        #if os(tvOS)
        180
        #elseif os(macOS)
        140
        #else
        sizeClass == .compact ? 90 : 124
        #endif
    }

    var body: some View {
        let resolvedHeight = height ?? (width.map { $0 / aspectRatio } ?? defaultHeight)
        let resolvedWidth = width ?? (height.map { $0 * aspectRatio } ?? resolvedHeight * aspectRatio)
        MediaCard(
            size: CGSize(width: resolvedWidth, height: resolvedHeight),
            media: media,
            artworkKind: ArtworkSelectionPolicy.landscapeCardArtworkKind(
                preferredArtworkKind: preferredArtworkKind
            ),
            showsLabels: showsLabels,
            onTap: onTap
        )
    }
}

#if os(tvOS)
private struct PlinxLibraryRecommendedRowsView: View {
    @Environment(MediaFocusModel.self) private var focusModel

    @State var viewModel: LibraryRecommendedViewModel
    @Binding var heroMedia: MediaItem?
    let usesLandscapeCards: Bool
    let onSelectMedia: (MediaDisplayItem) -> Void

    private let landscapeHubIdentifiers: [String] = ["inprogress"]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(viewModel.hubs) { hub in
                if hub.hasItems {
                    MediaHubSection(title: hub.title) {
                        carousel(for: hub)
                    }
                }
            }

            if viewModel.isLoading, !viewModel.hasContent {
                PlinxLoadingStateView(
                    role: .content,
                    label: LocalizedStringResource(
                        "library.recommended.loading",
                        table: "Plinx"
                    )
                )
                    .frame(maxWidth: .infinity)
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if !viewModel.hasContent, !viewModel.isLoading {
                Text("common.empty.nothingToShow")
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: focusModel.focusedMedia?.id) { _, _ in
            updateHeroMedia()
        }
        .onChange(of: viewModel.hubs.count) { _, _ in
            updateHeroMedia()
        }
        .onAppear {
            updateHeroMedia()
            updateInitialFocus()
        }
    }

    @ViewBuilder
    private func carousel(for hub: Hub) -> some View {
        if shouldUseLandscape(for: hub) {
            PlinxLibraryLandscapeCarousel(
                items: hub.items,
                showsLabels: true,
                onSelectMedia: onSelectMedia
            )
        } else {
            MediaCarousel(
                layout: .portrait,
                items: hub.items,
                showsLabels: true,
                onSelectMedia: onSelectMedia
            )
        }
    }

    private func shouldUseLandscape(for hub: Hub) -> Bool {
        if usesLandscapeCards {
            return true
        }
        let identifier = hub.id.lowercased()
        return landscapeHubIdentifiers.contains { identifier.contains($0) }
    }

    private var defaultHeroMedia: MediaItem? {
        for hub in viewModel.hubs where hub.hasItems {
            if let item = hub.items.compactMap(\.playableItem).first {
                return item
            }
        }
        return nil
    }

    private func updateHeroMedia() {
        if let focused = focusModel.focusedMedia {
            if heroMedia?.id != focused.id {
                heroMedia = focused
            }
            return
        }

        if heroMedia == nil {
            heroMedia = defaultHeroMedia
        }
    }

    private func updateInitialFocus() {
        guard focusModel.focusedMedia == nil else { return }
        if let initial = heroMedia ?? defaultHeroMedia {
            focusModel.focusedMedia = initial
        }
    }
}

private struct PlinxLibraryLandscapeCarousel: View {
    let items: [MediaDisplayItem]
    let showsLabels: Bool
    let onSelectMedia: (MediaDisplayItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 32) {
                ForEach(items, id: \.id) { media in
                    PlinxLibraryLandscapeMediaCard(media: media, showsLabels: showsLabels) {
                        onSelectMedia(media)
                    }
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
        }
        .mouseDragScrolling()
        .scrollClipDisabled()
        .focusSection()
    }
}

private struct PlinxLibraryBrowseRowsView: View {
    @Environment(MediaFocusModel.self) private var focusModel
    @FocusState private var focusedCharacterId: String?

    @State var viewModel: LibraryBrowseViewModel
    @Binding var heroMedia: MediaItem?
    let usesLandscapeCards: Bool
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onJumpToIndex: (Int) -> Void

    private var cardWidth: CGFloat {
        usesLandscapeCards ? 320 : 200
    }

    private var cardHeight: CGFloat? {
        usesLandscapeCards ? (cardWidth / (16.0 / 9.0)) : nil
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth), spacing: 32)]
    }

    var body: some View {
        @Bindable var controls = viewModel.controls

        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 24) {
                if controls.hasDisplayTypes {
                    LibraryBrowseControlsView(
                        viewModel: controls,
                        showsBackButton: viewModel.canNavigateBack,
                        onNavigateBack: viewModel.navigateBack
                    )
                }

                LazyVGrid(columns: gridColumns, spacing: 32) {
                    ForEach(0 ..< viewModel.totalItemCount, id: \.self) { index in
                        Group {
                            if let item = viewModel.itemsByIndex[index] {
                                switch item {
                                case let .media(media):
                                    if usesLandscapeCards {
                                        PlinxLibraryLandscapeMediaCard(media: media, width: cardWidth, showsLabels: true) {
                                            onSelectMedia(media)
                                        }
                                    } else {
                                        PortraitMediaCard(media: media, width: cardWidth, showsLabels: true) {
                                            onSelectMedia(media)
                                        }
                                    }
                                case let .folder(folder):
                                    FolderCard(title: folder.title, height: cardHeight, width: cardWidth, showsLabels: true) {
                                        viewModel.enterFolder(folder)
                                    }
                                }
                            } else {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .id(index)
                        .onAppear {
                            Task {
                                await viewModel.loadPagesAround(index: index)
                            }
                        }
                    }
                }

                if viewModel.isLoading, viewModel.itemsByIndex.isEmpty {
                    PlinxLoadingStateView(
                        role: .content,
                        label: LocalizedStringResource(
                            "library.browse.loading",
                            table: "Plinx"
                        )
                    )
                        .frame(maxWidth: .infinity)
                } else if let errorMessage = viewModel.errorMessage, viewModel.itemsByIndex.isEmpty {
                    ContentUnavailableView(
                        errorMessage,
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text("common.errors.tryAgainLater")
                    )
                    .symbolRenderingMode(.multicolor)
                } else if viewModel.totalItemCount == 0, !viewModel.isLoading {
                    ContentUnavailableView(
                        "library.browse.empty.title",
                        systemImage: "square.grid.2x2.fill",
                        description: Text("library.browse.empty.description")
                    )
                }
            }

            if viewModel.showsCharacterColumn {
                characterColumn(
                    characters: viewModel.sectionCharacters,
                    onSelect: { startIndex in
                        Task {
                            await viewModel.loadPagesAround(index: startIndex)
                            onJumpToIndex(startIndex)
                        }
                    }
                )
            }
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: focusModel.focusedMedia?.id) { _, _ in
            updateHeroMedia()
        }
        .onAppear {
            updateHeroMedia()
            updateInitialFocus()
        }
    }

    private var defaultHeroMedia: MediaItem? {
        for index in 0 ..< viewModel.totalItemCount {
            if case let .media(media)? = viewModel.itemsByIndex[index],
               let playable = media.playableItem
            {
                return playable
            }
        }
        return nil
    }

    private func updateHeroMedia() {
        if let focused = focusModel.focusedMedia {
            if heroMedia?.id != focused.id {
                heroMedia = focused
            }
            return
        }

        if heroMedia == nil {
            heroMedia = defaultHeroMedia
        }
    }

    private func updateInitialFocus() {
        guard focusModel.focusedMedia == nil else { return }
        if let initial = heroMedia ?? defaultHeroMedia {
            focusModel.focusedMedia = initial
        }
    }

    private func characterColumn(
        characters: [LibraryBrowseViewModel.SectionCharacter],
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        VStack(spacing: 4) {
            ForEach(characters) { character in
                characterButton(
                    id: character.id,
                    title: character.title,
                    onTap: { onSelect(character.startIndex) }
                )
            }
        }
        .padding(.trailing, 12)
        .padding(.top, 8)
        .frame(width: 44, alignment: .top)
    }

    private func characterButton(id: String, title: String, onTap: @escaping () -> Void) -> some View {
        let isFocused = focusedCharacterId == id
        return Button {
            onTap()
        } label: {
            Text(title)
                .font(.caption2)
                .frame(width: 32, height: 32)
                .background(isFocused ? Color.white.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($focusedCharacterId, equals: id)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

private struct PlinxLibraryCollectionsRowsView: View {
    @Environment(MediaFocusModel.self) private var focusModel
    @FocusState private var focusedCharacterId: String?

    @State var viewModel: LibraryCollectionsViewModel
    @Binding var heroMedia: MediaItem?
    let usesLandscapeCards: Bool
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onJumpToIndex: (Int) -> Void

    private var cardWidth: CGFloat {
        usesLandscapeCards ? 320 : 200
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth), spacing: 32)]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 24) {
                LazyVGrid(columns: gridColumns, spacing: 32) {
                    ForEach(0 ..< viewModel.totalItemCount, id: \.self) { index in
                        Group {
                            if let media = viewModel.itemsByIndex[index] {
                                if usesLandscapeCards {
                                    LandscapeMediaCard(media: media, width: cardWidth, showsLabels: true) {
                                        onSelectMedia(media)
                                    }
                                } else {
                                    PortraitMediaCard(media: media, width: cardWidth, showsLabels: true) {
                                        onSelectMedia(media)
                                    }
                                }
                            } else {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .id(index)
                        .onAppear {
                            Task {
                                await viewModel.loadPagesAround(index: index)
                            }
                        }
                    }
                }

                if viewModel.isLoading, viewModel.itemsByIndex.isEmpty {
                    PlinxLoadingStateView(
                        role: .content,
                        label: LocalizedStringResource(
                            "library.browse.loading",
                            table: "Plinx"
                        )
                    )
                        .frame(maxWidth: .infinity)
                } else if let errorMessage = viewModel.errorMessage, viewModel.itemsByIndex.isEmpty {
                    ContentUnavailableView(
                        errorMessage,
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text("common.errors.tryAgainLater")
                    )
                    .symbolRenderingMode(.multicolor)
                } else if viewModel.totalItemCount == 0, !viewModel.isLoading {
                    ContentUnavailableView(
                        "library.browse.empty.title",
                        systemImage: "square.grid.2x2.fill",
                        description: Text("library.browse.empty.description")
                    )
                }
            }

            characterColumn(
                characters: viewModel.sectionCharacters,
                onSelect: { startIndex in
                    Task {
                        await viewModel.loadPagesAround(index: startIndex)
                        onJumpToIndex(startIndex)
                    }
                }
            )
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: focusModel.focusedMedia?.id) { _, _ in
            updateHeroMedia()
        }
        .onAppear {
            updateHeroMedia()
            updateInitialFocus()
        }
    }

    private func characterColumn(
        characters: [LibraryCollectionsViewModel.SectionCharacter],
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        VStack(spacing: 4) {
            ForEach(characters) { character in
                characterButton(
                    id: character.id,
                    title: character.title,
                    onTap: { onSelect(character.startIndex) }
                )
            }
        }
        .padding(.trailing, 12)
        .padding(.top, 8)
        .frame(width: 44, alignment: .top)
    }

    private func characterButton(id: String, title: String, onTap: @escaping () -> Void) -> some View {
        let isFocused = focusedCharacterId == id
        return Button {
            onTap()
        } label: {
            Text(title)
                .font(.caption2)
                .frame(width: 32, height: 32)
                .background(isFocused ? Color.white.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($focusedCharacterId, equals: id)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }

    private var defaultHeroMedia: MediaItem? {
        for index in 0 ..< viewModel.totalItemCount {
            if let media = viewModel.itemsByIndex[index], let playable = media.playableItem {
                return playable
            }
        }
        return nil
    }

    private func updateHeroMedia() {
        if let focused = focusModel.focusedMedia {
            if heroMedia?.id != focused.id {
                heroMedia = focused
            }
            return
        }

        if heroMedia == nil {
            heroMedia = defaultHeroMedia
        }
    }

    private func updateInitialFocus() {
        guard focusModel.focusedMedia == nil else { return }
        if let initial = heroMedia ?? defaultHeroMedia {
            focusModel.focusedMedia = initial
        }
    }
}
#endif

// MARK: - LibraryDetailTab icon extension (Plinx augmentation)

extension LibraryDetailTab {
    /// SF Symbol name used by `PlinxLibraryTabPicker`.
    var plinxIconName: String {
        switch self {
        case .recommended: return "star.fill"
        case .browse:      return "square.grid.2x2.fill"
        case .collections: return "rectangle.stack.fill"
        case .playlists:   return "music.note.list"
        }
    }
}

// MARK: - Kids icon-button tab picker

/// Large, tap-friendly icon-button tab bar for library navigation.
///
/// Uses bigger buttons on iPad (`.regular` size class) and slightly smaller
/// buttons on iPhone (`.compact`) — both optimised for children's motor accuracy.
private struct PlinxLibraryTabPicker: View {
    let tabs: [LibraryDetailTab]
    @Binding var selectedTab: LibraryDetailTab

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isRegular: Bool { sizeClass == .regular }

    private var buttonMinWidth: CGFloat   {
        #if os(tvOS)
        88
        #else
        isRegular ? 108 : 82
        #endif
    }
    private var buttonHeight: CGFloat     {
        #if os(tvOS)
        50
        #else
        isRegular ? 66 : 52
        #endif
    }
    private var iconPointSize: CGFloat    {
        #if os(tvOS)
        18
        #else
        isRegular ? 26 : 19
        #endif
    }
    private var labelFont: Font           {
        #if os(tvOS)
        .caption2
        #else
        isRegular ? .subheadline : .caption
        #endif
    }
    private var cornerRadius: CGFloat     {
        #if os(tvOS)
        14
        #else
        isRegular ? 16 : 12
        #endif
    }
    private var hSpacing: CGFloat         {
        #if os(tvOS)
        8
        #else
        isRegular ? 12 : 8
        #endif
    }
    private var iconLabelSpacing: CGFloat {
        #if os(tvOS)
        4
        #else
        isRegular ? 8 : 5
        #endif
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: hSpacing) {
                    ForEach(tabs) { tab in
                        tabButton(tab)
                    }
                }
                .frame(minWidth: proxy.size.width - 32, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
        .frame(height: buttonHeight + 8)
        .accessibilityIdentifier("library.detail.tabPicker")
    }

    private func tabButton(_ tab: LibraryDetailTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: iconLabelSpacing) {
                Image(systemName: tab.plinxIconName)
                    .font(.system(size: iconPointSize, weight: .semibold))
                Text(tab.title)
                    .font(labelFont.bold())
                    .lineLimit(1)
            }
            .frame(minWidth: buttonMinWidth, minHeight: buttonHeight)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.white.opacity(0.10))
            )
            .foregroundStyle(isSelected ? .white : .white.opacity(0.65))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isSelected ? Color.clear : Color.white.opacity(0.15),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
        .accessibilityIdentifier("library.detail.tab.\(tab.rawValue)")
    }
}
