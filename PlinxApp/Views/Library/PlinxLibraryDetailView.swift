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
