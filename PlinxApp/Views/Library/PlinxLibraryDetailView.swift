import OSLog
import PlinxCore
import PlinxUI
import SwiftUI

/// Plinx-specific library detail screen.
///
/// This view owns all kid-safety, branding, and navigation chrome for the
/// library drill-down. The underlying Strimr sub-views (`LibraryBrowseView`,
/// `LibraryRecommendedView`, `LibraryCollectionsView`) are generic and kept
/// clean in the Strimr fork; Plinx injects behaviour via the seams those
/// views expose (`itemFilter`, `hubFilter`, `topContent`, `overrideLayout`,
/// `onLongPressMedia`).
struct PlinxLibraryDetailView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Plinx",
        category: "LibraryDetailSafety"
    )

    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(\.safetyPolicy) private var safetyPolicy
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var mainCoordinator: MainCoordinator
    #if os(tvOS)
    @Environment(MediaFocusModel.self) private var mediaFocusModel
    #endif

    let library: Library
    let onSelectMedia: (MediaDisplayItem) -> Void
    var onLongPressMedia: (MediaDisplayItem) -> Void = { _ in }

    @State private var selectedTab: LibraryDetailTab = .recommended
    @State private var browseQuickSort: LibraryBrowseControlsViewModel.QuickSort = .newest
    @State private var browseRefreshIdentity = UUID()
    #if os(tvOS)
    @State private var tvHeroMedia: MediaItem?
    @FocusState private var focusedRootNavTab: MainCoordinator.Tab?
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
            focusedRootNavTab = .library
            focusedLibraryFilterTab = selectedTab
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
            LibraryRecommendedView(
                viewModel: makeRecommendedViewModel(),
                onSelectMedia: onSelectMedia,
                onLongPressMedia: onLongPressMedia,
                topContent: scrollingTopContent,
                overrideLayout: { _ in preferredCarouselLayout }
            )
            #endif
        case .browse:
            #if os(tvOS)
            LibraryBrowseView(
                viewModel: makeBrowseViewModel(),
                onSelectMedia: onSelectMedia
            )
            .id(browseRefreshIdentity)
            #else
            LibraryBrowseView(
                viewModel: makeBrowseViewModel(),
                onSelectMedia: onSelectMedia,
                onLongPressMedia: onLongPressMedia,
                topContent: scrollingTopContent,
                overrideLayout: preferredCarouselLayout,
                showsControls: false
            )
            .id(browseRefreshIdentity)
            #endif
        case .collections:
            #if os(tvOS)
            LibraryCollectionsView(
                viewModel: makeCollectionsViewModel(),
                onSelectMedia: onSelectMedia
            )
            #else
            LibraryCollectionsView(
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

                    if selectedTab == .browse {
                        browseQuickSortButtons
                            .padding(.trailing, 2)
                    }
                }
            }
            .padding(.top, 4)
        )
    }

    // MARK: - Tab helpers

    private var hasDownloadActivity: Bool {
        !downloadManager.items.isEmpty
    }

    private var activeRootTab: MainCoordinator.Tab {
        switch mainCoordinator.tab {
        case .search:
            return .search
        case .library, .libraryDetail(_):
            return .library
        case .more:
            return .more
        case .home, .seerrDiscover:
            return .home
        }
    }

    private var rootTabBinding: Binding<MainCoordinator.Tab> {
        Binding(
            get: { activeRootTab },
            set: { newValue in
                handleRootTabSelection(newValue)
            }
        )
    }

    private var visibleRootTabs: [KidsMainTabPicker.TabItem] {
        KidsMainTabPicker.TabItem.mainTabs(
            includeDownloads: hasDownloadActivity,
            showSearchInMainNavigation: true,
            includeSettings: false
        )
    }

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
                tvNavigationRow
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
                onSelectMedia: onSelectMedia
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        case .browse:
            PlinxLibraryBrowseRowsView(
                viewModel: makeBrowseViewModel(),
                heroMedia: $tvHeroMedia,
                onSelectMedia: onSelectMedia,
                onJumpToIndex: { index in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollProxy.scrollTo(index, anchor: .top)
                    }
                }
            )
            .id(browseRefreshIdentity)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        case .collections:
            PlinxLibraryCollectionsRowsView(
                viewModel: makeCollectionsViewModel(),
                heroMedia: $tvHeroMedia,
                onSelectMedia: onSelectMedia,
                onJumpToIndex: { index in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollProxy.scrollTo(index, anchor: .top)
                    }
                }
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        case .playlists:
            EmptyView()
        }
    }

    private var tvNavigationRow: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                    Text(library.title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .buttonStyle(TvPillButtonStyle(isSelected: false))

            KidsMainTabPicker(
                tabs: visibleRootTabs,
                selectedTab: rootTabBinding,
                focusedTab: $focusedRootNavTab,
                placement: .header
            )
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var tvFilterRow: some View {
        HStack(spacing: 10) {
            ForEach(availableTabs) { tab in
                tvFilterButton(tab: tab)
            }

            if selectedTab == .browse {
                browseQuickSortButtons
            }
        }
    }

    private func tvFilterButton(tab: LibraryDetailTab) -> some View {
        Button {
            selectedTab = tab
            focusedLibraryFilterTab = tab
        } label: {
            Text(tab.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .focused($focusedLibraryFilterTab, equals: tab)
        .buttonStyle(TvPillButtonStyle(isSelected: selectedTab == tab))
        .accessibilityIdentifier("library.detail.filter.\(tab.rawValue)")
    }

    private var tvHeaderContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Single row: [back + library name] overlaid with centered nav picker
            tvNavigationRow

            // Library sub-tabs (Recommended / Browse / Collections)
            tvFilterRow
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
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

    private func handleRootTabSelection(_ newValue: MainCoordinator.Tab) {
        mainCoordinator.resetToRoot(for: newValue)
        mainCoordinator.tab = newValue
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
        vm.controls.preferredQuickSort = browseQuickSort
        #if !os(tvOS)
        let policy = safetyPolicy
        let libType = library.type
        // None-agent libraries (YouTube Videos, Home Videos, etc.) are personally
        // curated and typically lack MPAA/TV content ratings. Allow unrated items
        // through while still respecting the rating ceiling for any item that does
        // carry an explicit rating (e.g., a TV-MA clip still gets blocked).
        let effectivePolicy = library.isNoneAgentLibrary
            ? SafetyPolicy.ratingOnly(maxMovie: policy.maxMovieRating, maxTV: policy.maxTVRating, allowUnrated: true)
            : policy
        vm.itemFilter = { item in
            if (libType == .movie || libType == .show), case .collection = item {
                return false
            }
            return StrimrAdapter.isAllowed(item, policy: effectivePolicy)
        }
        #endif
        return vm
    }

    private var browseQuickSortButtons: some View {
        HStack(spacing: 8) {
            if selectedTab == .browse {
                quickSortButton(
                    iconName: "textformat.abc",
                    accessibilityID: "library.browse.sort.alphabetical",
                    quickSort: .alphabetical
                )

                quickSortButton(
                    iconName: "clock.arrow.circlepath",
                    accessibilityID: "library.browse.sort.new",
                    quickSort: .newest
                )
            }
        }
    }

    private func quickSortButton(
        iconName: String,
        accessibilityID: String,
        quickSort: LibraryBrowseControlsViewModel.QuickSort
    ) -> some View {
        let isSelected = browseQuickSort == quickSort

        return Button {
            guard browseQuickSort != quickSort else { return }
            browseQuickSort = quickSort
            browseRefreshIdentity = UUID()
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .frame(minWidth: 58, minHeight: 58)
        }
        .buttonStyle(TvPillButtonStyle(isSelected: isSelected))
        .accessibilityIdentifier(accessibilityID)
    }

    private func makeCollectionsViewModel() -> LibraryCollectionsViewModel {
        #if os(tvOS)
        let vm = LibraryCollectionsViewModel(
            library: library,
            context: plexApiContext,
            settingsManager: settingsManager
        )
        #else
        let vm = LibraryCollectionsViewModel(library: library, context: plexApiContext)
        let policy = safetyPolicy
        vm.itemFilter = { item in
            StrimrAdapter.isAllowed(item, policy: policy)
        }
        #endif
        return vm
    }

    private func filterRecommendedHub(_ hub: Hub, policy: SafetyPolicy) -> Hub? {
        guard let safetyFiltered = StrimrAdapter.filtered(hub, policy: policy) else {
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

#if os(tvOS)
private struct PlinxLibraryRecommendedRowsView: View {
    @Environment(MediaFocusModel.self) private var focusModel
    @Environment(\.preferredLandscapeArtworkKind) private var preferredLandscapeArtworkKind

    @State var viewModel: LibraryRecommendedViewModel
    @Binding var heroMedia: MediaItem?
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
                ProgressView("library.recommended.loading")
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
            MediaCarousel(
                layout: .landscape,
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
        if preferredLandscapeArtworkKind != nil {
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

private struct PlinxLibraryBrowseRowsView: View {
    @Environment(MediaFocusModel.self) private var focusModel
    @Environment(\.preferredLandscapeArtworkKind) private var preferredLandscapeArtworkKind
    @FocusState private var focusedCharacterId: String?

    @State var viewModel: LibraryBrowseViewModel
    @Binding var heroMedia: MediaItem?
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onJumpToIndex: (Int) -> Void

    private var usesLandscapeCards: Bool {
        preferredLandscapeArtworkKind != nil
    }

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
                                        LandscapeMediaCard(media: media, width: cardWidth, showsLabels: true) {
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
                    ProgressView("library.browse.loading")
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
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onJumpToIndex: (Int) -> Void

    private let gridColumns = [
        GridItem(.adaptive(minimum: 200, maximum: 200), spacing: 32),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 24) {
                LazyVGrid(columns: gridColumns, spacing: 32) {
                    ForEach(0 ..< viewModel.totalItemCount, id: \.self) { index in
                        Group {
                            if let media = viewModel.itemsByIndex[index] {
                                PortraitMediaCard(media: media, width: 200, showsLabels: true) {
                                    onSelectMedia(media)
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
                    ProgressView("library.browse.loading")
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
