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
    @FocusState private var focusedLibraryFilterTab: LibraryDetailTab?
    @State private var contentFocusGeneration = 0
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
        .onDisappear {
            // Tab selection updates focus ownership before this view leaves.
            // Only restore the Library root when this detail still owns it.
            guard tvFocusCoordinator.activeContentRegion == .libraryDetail else { return }
            tvFocusCoordinator.activate(.library)
        }
        .onChange(of: contentFocusRequest) { _, _ in
            let target = availableTabs.contains(selectedTab)
                ? selectedTab
                : availableTabs.first
            contentFocusGeneration &+= 1
            let generation = contentFocusGeneration
            focusedLibraryFilterTab = nil
            guard let target else { return }
            Task { @MainActor in
                await Task.yield()
                guard generation == contentFocusGeneration else { return }
                focusedLibraryFilterTab = target
            }
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
                EmptyView()
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
            .padding(.horizontal, TvBrowseHeroMetrics.alignedContentInset)
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
            .padding(.horizontal, TvBrowseHeroMetrics.alignedContentInset)
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
            .padding(.horizontal, TvBrowseHeroMetrics.alignedContentInset)
            .padding(.bottom, 28)
        case .playlists:
            EmptyView()
        }
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
            contentFocusGeneration &+= 1
            onRequestShellNavigationFocus()
        }
    }

    private var tvHeaderContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .frame(height: PlinxTVShellMetrics.contentClearance + 12)
                .accessibilityHidden(true)

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

enum LibraryRecommendationFallbackPolicy {
    static let discoveryHubID = "plinx.discovery.recentlyAdded"

    static func needsDiscoveryHub(_ hubs: [Hub]) -> Bool {
        !hubs.contains { $0.hasItems && !isContinuationHub($0) }
    }

    static func discoveryItems(
        from candidates: [MediaDisplayItem],
        excluding hubs: [Hub],
        limit: Int = 24
    ) -> [MediaDisplayItem] {
        let existingIDs = Set(hubs.flatMap { $0.items.map(\.id) })
        var seen = existingIDs
        var items: [MediaDisplayItem] = []

        for candidate in candidates where seen.insert(candidate.id).inserted {
            items.append(candidate)
            if items.count == limit { break }
        }
        return items
    }

    private static func isContinuationHub(_ hub: Hub) -> Bool {
        let normalized = (hub.id + hub.title)
            .lowercased()
            .filter(\.isLetter)
        return normalized.contains("inprogress") || normalized.contains("continuewatching")
    }
}

@MainActor
private enum PlinxLibraryRecommendationLoader {
    static func load(
        viewModel: LibraryRecommendedViewModel,
        context: PlexAPIContext,
        settingsManager: SettingsManager,
        policy: SafetyPolicy,
        refreshIfNeeded: Bool = false
    ) async {
        if refreshIfNeeded {
            await viewModel.refreshIfNeeded()
        } else {
            await viewModel.load()
        }

        var hubs = viewModel.hubs
        if LibraryRecommendationFallbackPolicy.needsDiscoveryHub(hubs) {
            if let catalog = try? await LibraryCatalogLoader(context: context).recentItems(
                for: viewModel.library,
                limit: 120,
                policy: policy
            ) {
                let items = LibraryRecommendationFallbackPolicy.discoveryItems(
                    from: catalog.items,
                    excluding: hubs
                )
                if !items.isEmpty {
                    hubs.append(
                        Hub(
                            id: LibraryRecommendationFallbackPolicy.discoveryHubID,
                            title: String(localized: "home.recentlyAdded.prefix", table: "Plinx"),
                            items: items
                        )
                    )
                }
            }
        }

        viewModel.hubs = visibleOrderedHubs(
            hubs,
            libraryID: viewModel.library.id,
            settingsManager: settingsManager
        )
    }

    private static func visibleOrderedHubs(
        _ hubs: [Hub],
        libraryID: String,
        settingsManager: SettingsManager
    ) -> [Hub] {
        let configuration = settingsManager.plinxLibraryViewSettings(for: libraryID)
        let hiddenIDs = Set(configuration.hiddenRecommendSectionIds)
        var seenIDs = Set<String>()
        let visible = hubs.filter {
            !hiddenIDs.contains($0.id) && seenIDs.insert($0.id).inserted
        }
        let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        let ordered = configuration.recommendSectionOrder.compactMap { byID[$0] }
        let orderedIDs = Set(ordered.map(\.id))
        return ordered + visible.filter { !orderedIDs.contains($0.id) }
    }
}

private struct PlinxLibraryHubSection<Content: View>: View {
    let title: String
    let onViewAll: (() -> Void)?
    @ViewBuilder let content: Content

    init(
        title: String,
        onViewAll: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.onViewAll = onViewAll
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                titleView
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 40, height: 4)
            }
            .padding(.horizontal, 2)

            content
        }
    }

    @ViewBuilder
    private var titleView: some View {
        #if os(tvOS)
        titleText
        #else
        if let onViewAll {
            Button(action: onViewAll) {
                HStack(spacing: 5) {
                    titleText
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("hub.viewAll"))
        } else {
            titleText
        }
        #endif
    }

    private var titleText: some View {
        Text(title)
            #if os(tvOS)
            .font(.system(size: 30, weight: .bold, design: .rounded))
            #else
            .font(.headline.weight(.semibold))
            #endif
            .foregroundStyle(.brandSecondary)
    }
}

#if !os(tvOS)
private struct PlinxLibraryRecommendedContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.safetyPolicy) private var safetyPolicy

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
                        PlinxLibraryHubSection(
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
            await PlinxLibraryRecommendationLoader.load(
                viewModel: viewModel,
                context: plexApiContext,
                settingsManager: settingsManager,
                policy: safetyPolicy
            )
        }
        .onAppear {
            Task {
                await PlinxLibraryRecommendationLoader.load(
                    viewModel: viewModel,
                    context: plexApiContext,
                    settingsManager: settingsManager,
                    policy: safetyPolicy,
                    refreshIfNeeded: true
                )
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task {
                await PlinxLibraryRecommendationLoader.load(
                    viewModel: viewModel,
                    context: plexApiContext,
                    settingsManager: settingsManager,
                    policy: safetyPolicy,
                    refreshIfNeeded: true
                )
            }
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
            PlinxLibraryPortraitMediaCard(media: media, showsLabels: true) {
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
                PlinxLibraryPortraitMediaCard(media: media, width: cardWidth, showsLabels: true) {
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
                        PlinxLibraryPortraitMediaCard(media: media, width: cardWidth, showsLabels: true) {
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

private struct PlinxLibraryPortraitMediaCard: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    let media: MediaDisplayItem
    let height: CGFloat?
    let width: CGFloat?
    let showsLabels: Bool
    let onTap: () -> Void

    private let aspectRatio: CGFloat = 2 / 3

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
        320
        #elseif os(macOS)
        260
        #else
        sizeClass == .compact ? 180 : 240
        #endif
    }

    var body: some View {
        let resolvedHeight = height ?? (width.map { $0 / aspectRatio } ?? defaultHeight)
        let resolvedWidth = width ?? (height.map { $0 * aspectRatio } ?? resolvedHeight * aspectRatio)
        PlinxLibraryMediaCard(
            size: CGSize(width: resolvedWidth, height: resolvedHeight),
            media: media,
            artworkKind: .thumb,
            showsLabels: showsLabels,
            onTap: onTap
        )
    }
}

/// Plinx's library-detail landscape card honors the library-specific artwork
/// preference so Other Videos displays each item's Plex thumbnail.
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
        PlinxLibraryMediaCard(
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

/// One Plinx-owned media-card renderer for every library surface. Keeping the
/// focus decoration here prevents individual tabs from drifting back to the
/// inset-ring behavior of the upstream card.
private struct PlinxLibraryMediaCard: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    #if os(tvOS)
    @Environment(MediaFocusModel.self) private var focusModel
    @FocusState private var isFocused: Bool
    #endif

    let size: CGSize
    let media: MediaDisplayItem
    let artworkKind: MediaImageViewModel.ArtworkKind
    let showsLabels: Bool
    let onTap: () -> Void

    private let cornerRadius: CGFloat = 14

    private var progress: Double? {
        media.viewProgressPercentage.map { min(max($0 / 100, 0), 1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: labelSpacing) {
            artwork

            if showsLabels {
                VStack(alignment: .leading, spacing: 4) {
                    Text(media.primaryLabel)
                        .font(primaryLabelFont)
                        .lineLimit(1)

                    if let secondaryLabel = media.secondaryLabel, !secondaryLabel.isEmpty {
                        Text(secondaryLabel)
                            .font(secondaryLabelFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let tertiaryLabel = media.tertiaryLabel, !tertiaryLabel.isEmpty {
                        Text(tertiaryLabel)
                            .font(secondaryLabelFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(width: size.width, alignment: .leading)
        #if os(tvOS)
        .focusable()
        .focused($isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused, let playableItem = media.playableItem {
                focusModel.focusedMedia = playableItem
            }
        }
        .onPlayPauseCommand(perform: onTap)
        #endif
        .onTapGesture(perform: onTap)
    }

    private var artwork: some View {
        MediaImageView(
            viewModel: MediaImageViewModel(
                context: plexApiContext,
                artworkKind: artworkKind,
                media: media
            )
        )
        .frame(width: size.width, height: size.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            WatchStatusBadge(media: media)
        }
        .overlay(alignment: .bottomLeading) {
            if let progress, progress > 0 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        }
        #if os(tvOS)
        .plinxTVCardFocusArtwork(isFocused: isFocused, cornerRadius: cornerRadius)
        #endif
    }

    private var labelSpacing: CGFloat {
        #if os(tvOS)
        12
        #else
        8
        #endif
    }

    private var primaryLabelFont: Font {
        #if os(tvOS)
        size.width < 180 ? .footnote : .subheadline
        #else
        .subheadline
        #endif
    }

    private var secondaryLabelFont: Font {
        #if os(tvOS)
        size.width < 180 ? .caption2 : .footnote
        #else
        .footnote
        #endif
    }
}

#if os(tvOS)
private struct PlinxLibraryRecommendedRowsView: View {
    @Environment(MediaFocusModel.self) private var focusModel
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.safetyPolicy) private var safetyPolicy

    @State var viewModel: LibraryRecommendedViewModel
    @Binding var heroMedia: MediaItem?
    let usesLandscapeCards: Bool
    let onSelectMedia: (MediaDisplayItem) -> Void

    private let landscapeHubIdentifiers: [String] = ["inprogress"]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(viewModel.hubs) { hub in
                if hub.hasItems {
                    PlinxLibraryHubSection(title: hub.title) {
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
            await PlinxLibraryRecommendationLoader.load(
                viewModel: viewModel,
                context: plexApiContext,
                settingsManager: settingsManager,
                policy: safetyPolicy
            )
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
            PlinxLibraryPortraitCarousel(
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
            .padding(.trailing, 16)
        }
        .mouseDragScrolling()
        .scrollClipDisabled()
        .focusSection()
    }
}

private struct PlinxLibraryPortraitCarousel: View {
    let items: [MediaDisplayItem]
    let showsLabels: Bool
    let onSelectMedia: (MediaDisplayItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 32) {
                ForEach(items, id: \.id) { media in
                    PlinxLibraryPortraitMediaCard(media: media, showsLabels: showsLabels) {
                        onSelectMedia(media)
                    }
                }
            }
            .padding(.vertical, 16)
            .padding(.trailing, 16)
        }
        .mouseDragScrolling()
        .scrollClipDisabled()
        .focusSection()
    }
}

/// Plinx-owned browse controls keep all library filters on the shared dark
/// focus treatment instead of allowing tvOS to add its bright white plate.
private struct PlinxLibraryBrowseControlsView: View {
    @Bindable var viewModel: LibraryBrowseControlsViewModel
    let showsBackButton: Bool
    let onNavigateBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topRow

            if let panel = viewModel.activePanel {
                optionsRow(for: panel)
            }
        }
        .sheet(item: $viewModel.activeFilterSheet) { sheet in
            PlinxLibraryBrowseFilterSheetView(viewModel: viewModel, filter: sheet.filter)
        }
    }

    private var topRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                if showsBackButton {
                    pill(
                        title: String(localized: "library.browse.folders.back"),
                        systemImage: "chevron.left",
                        isSelected: false,
                        action: onNavigateBack
                    )
                }

                pill(
                    title: viewModel.typePillTitle,
                    systemImage: "square.grid.2x2",
                    isSelected: viewModel.activePanel == .type,
                    showsDisclosure: true
                ) {
                    viewModel.togglePanel(.type)
                }

                if viewModel.showsFilterPill {
                    pill(
                        title: viewModel.filterPillTitle,
                        systemImage: "line.3.horizontal.decrease.circle",
                        isSelected: viewModel.activePanel == .filters || !viewModel.selectedFilters.isEmpty,
                        showsDisclosure: true
                    ) {
                        viewModel.togglePanel(.filters)
                    }
                }

                if viewModel.showsSortPill {
                    pill(
                        title: viewModel.sortPillTitle,
                        systemImage: "arrow.up.arrow.down.circle",
                        isSelected: viewModel.activePanel == .sort || viewModel.selectedSort != nil,
                        showsDisclosure: true
                    ) {
                        viewModel.togglePanel(.sort)
                    }
                }
            }
            .padding(.trailing, 16)
            .padding(.vertical, 12)
        }
        .mouseDragScrolling()
        .scrollClipDisabled()
        .focusSection()
    }

    @ViewBuilder
    private func optionsRow(for panel: LibraryBrowseControlsViewModel.Panel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                switch panel {
                case .type:
                    ForEach(viewModel.displayTypes) { type in
                        pill(
                            title: type.title,
                            systemImage: nil,
                            isSelected: type.key == viewModel.selectedDisplayType?.key
                        ) {
                            viewModel.selectDisplayType(type)
                        }
                    }
                case .filters:
                    ForEach(viewModel.availableFilters, id: \.filter) { filter in
                        let selection = viewModel.filterSelection(for: filter)
                        let isSelected = selection?.isEnabled == true
                        pill(
                            title: filterLabel(for: filter, selection: selection),
                            systemImage: isSelected ? "checkmark" : nil,
                            isSelected: isSelected,
                            showsDisclosure: !filter.isBoolean
                        ) {
                            viewModel.toggleFilter(filter)
                        }
                    }
                case .sort:
                    ForEach(viewModel.availableSorts, id: \.key) { sort in
                        let selection = viewModel.selectedSort
                        let isSelected = selection?.sort.key == sort.key
                        pill(
                            title: sort.title,
                            systemImage: sortDirectionImage(for: selection, sort: sort),
                            isSelected: isSelected
                        ) {
                            viewModel.toggleSort(sort)
                        }
                    }
                }
            }
            .padding(.trailing, 16)
            .padding(.vertical, 10)
        }
        .mouseDragScrolling()
        .scrollClipDisabled()
        .focusSection()
    }

    private func pill(
        title: String,
        systemImage: String?,
        isSelected: Bool,
        showsDisclosure: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if showsDisclosure {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .opacity(0.72)
                }
            }
        }
        .buttonStyle(TvPillButtonStyle(isSelected: isSelected, cornerRadius: 18))
        .focusEffectDisabled()
    }

    private func filterLabel(
        for filter: PlexSectionItemFilter,
        selection: LibraryBrowseControlsViewModel.FilterSelection?
    ) -> String {
        guard let option = selection?.selectedOption else { return filter.title }
        return filter.title + ": " + option.title
    }

    private func sortDirectionImage(
        for selection: LibraryBrowseControlsViewModel.SortSelection?,
        sort: PlexSectionItemSort
    ) -> String? {
        guard let selection, selection.sort.key == sort.key else { return nil }
        return selection.direction == .asc ? "arrow.up" : "arrow.down"
    }
}

private struct PlinxLibraryBrowseFilterSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: LibraryBrowseControlsViewModel
    let filter: PlexSectionItemFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Text(filter.title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                if viewModel.filterSelection(for: filter) != nil {
                    headerButton(title: String(localized: "library.browse.filters.clear")) {
                        viewModel.clearFilter(filter)
                        dismiss()
                    }
                }

                headerButton(title: String(localized: "common.actions.done")) {
                    dismiss()
                }
            }

            content
        }
        .padding(42)
        .background(Color.appBackground.ignoresSafeArea())
        .onExitCommand { dismiss() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoadingOptions(for: filter) {
            PlinxLoadingStateView(
                role: .content,
                label: LocalizedStringResource("library.browse.filters.loading")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.optionsError(for: filter) {
            ContentUnavailableView(
                errorMessage,
                systemImage: "exclamationmark.triangle.fill",
                description: Text("common.errors.tryAgainLater")
            )
            .symbolRenderingMode(.multicolor)
        } else if viewModel.options(for: filter).isEmpty {
            ContentUnavailableView(
                "common.empty.nothingToShow",
                systemImage: "line.3.horizontal.decrease.circle"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.options(for: filter)) { option in
                        let isSelected = viewModel.filterSelection(for: filter)?.selectedOption?.id == option.id
                        Button {
                            viewModel.selectFilterOption(option, for: filter)
                            dismiss()
                        } label: {
                            HStack {
                                Text(option.title)
                                    .font(.system(size: 26, weight: .semibold))
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 26, weight: .bold))
                                }
                            }
                        }
                        .buttonStyle(TvPillButtonStyle(isSelected: isSelected, cornerRadius: 18))
                        .focusEffectDisabled()
                    }
                }
                .padding(.vertical, 10)
            }
        }
    }

    private func headerButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(TvPillButtonStyle(isSelected: false, cornerRadius: 18))
            .focusEffectDisabled()
    }
}

private struct PlinxLibraryBrowseRowsView: View {
    @Environment(MediaFocusModel.self) private var focusModel
    @FocusState private var focusedCharacterId: String?

    @State var viewModel: LibraryBrowseViewModel
    @State private var isPrefetchingCompleteCatalog = false
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
            VStack(alignment: .leading, spacing: 14) {
                if controls.hasDisplayTypes {
                    PlinxLibraryBrowseControlsView(
                        viewModel: controls,
                        showsBackButton: viewModel.canNavigateBack,
                        onNavigateBack: viewModel.navigateBack
                    )
                }

                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 32) {
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
                                        PlinxLibraryPortraitMediaCard(media: media, width: cardWidth, showsLabels: true) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await loadCompleteFilteredCatalog()
        }
        .onChange(of: focusModel.focusedMedia?.id) { _, _ in
            updateHeroMedia()
        }
        .onChange(of: viewModel.totalItemCount) { _, _ in
            updateHeroMedia()
        }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            guard !isLoading else { return }
            Task { await loadCompleteFilteredCatalog() }
        }
        .onAppear {
            updateHeroMedia()
            updateInitialFocus()
        }
    }

    /// Safety filtering happens client-side, so the upstream paged model only
    /// knows about the first allowed batch at initial load. Advance until the
    /// filtered count stops growing so Browse represents the complete library.
    private func loadCompleteFilteredCatalog() async {
        guard !isPrefetchingCompleteCatalog else { return }
        isPrefetchingCompleteCatalog = true
        defer { isPrefetchingCompleteCatalog = false }

        await viewModel.load()

        var previousCount: Int?
        for _ in 0 ..< 300 {
            guard !Task.isCancelled else { return }
            let currentCount = viewModel.totalItemCount
            guard previousCount != currentCount else { return }
            previousCount = currentCount
            await viewModel.loadPagesAround(index: max(currentCount - 1, 0))
            await Task.yield()
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
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 32) {
                    ForEach(0 ..< viewModel.totalItemCount, id: \.self) { index in
                        Group {
                            if let media = viewModel.itemsByIndex[index] {
                                if usesLandscapeCards {
                                    PlinxLibraryLandscapeMediaCard(media: media, width: cardWidth, showsLabels: true) {
                                        onSelectMedia(media)
                                    }
                                } else {
                                    PlinxLibraryPortraitMediaCard(media: media, width: cardWidth, showsLabels: true) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
