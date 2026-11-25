import SwiftUI
import UIKit
import PlinxUI
import PlinxCore
import OSLog

#if os(tvOS)
enum HomeVerticalFocusDirection {
    case up
    case down
}

enum HomeVerticalFocusRoute: Equatable {
    case navigation
    case card(row: Int, item: Int)
    case unchanged
}

enum HomeVerticalFocusRouting {
    static func nextRoute(
        direction: HomeVerticalFocusDirection,
        fromRow rowIndex: Int,
        rowCount: Int
    ) -> HomeVerticalFocusRoute {
        switch direction {
        case .up:
            if rowIndex == 0 {
                return .navigation
            }
            return .card(row: rowIndex - 1, item: 0)
        case .down:
            guard rowIndex + 1 < rowCount else { return .unchanged }
            return .card(row: rowIndex + 1, item: 0)
        }
    }
}

enum HomeHeroSelection {
    static func resolvedMediaID(currentID: String?, availableIDs: [String]) -> String? {
        if let currentID, availableIDs.contains(currentID) {
            return currentID
        }
        return availableIDs.first
    }
}
#endif

/// The kid-facing Home: Continue Watching from the absorbed `HomeViewModel`
/// (merged across the profile's servers), then Plinx's recently-added rows
/// built from each visible library (`HomeRecentlyAddedStore` and
/// `HomeRecentlyAddedProjection`). Every title arrives through the safety
/// boundary in `MediaServices`; rows are filtered again with
/// `ContentSafetyGate` when drawn, so a stricter policy hides titles at once.
struct PlinxHomeView: View {
    private static let logger = Logger(subsystem: "com.bballdavis.plinx", category: "home")

    @State var viewModel: HomeViewModel
    var topContent: AnyView? = nil
    var onSelectMedia: (MediaDisplayItem) -> Void
    var onLongPressMedia: (MediaDisplayItem) -> Void = { _ in }
    var onRequestHomeNavigationFocus: () -> Void = {}
    var contentFocusRequest: Int = 0
    /// Returns whether a given display item should show as watched.
    /// Injected by parent to reflect optimistic local overrides.
    var isItemWatched: (MediaDisplayItem) -> Bool = { $0.isFullyWatched }

    @Environment(ServerRegistry.self) private var registry
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var mainCoordinator: MainCoordinator
    @State private var recentlyAdded = HomeRecentlyAddedStore()
    @State private var artworkRefreshToken = UUID()
    #if os(tvOS)
    @Environment(MediaFocusModel.self) private var mediaFocusModel
    @EnvironmentObject private var tvFocusCoordinator: PlinxTVFocusCoordinator
    @FocusState private var focusedCard: HomeFocusTarget?
    @State private var selectedHeroMedia: MediaItem?
    @State private var isContentFocusPending = false
    @State private var contentFocusGeneration = 0
    #endif

    // Plinx-specific home screen settings (separate from Library-tab visibility)
    @AppStorage("plinx.homeHiddenLibraryIds") private var homeHiddenIdsJson = "[]"
    @AppStorage("plinx.homeLibraryOrder") private var homeOrderJson = "[]"
    @AppStorage("plinx.homeSectionOrder") private var homeSectionOrderJson = "[]"
    @AppStorage("plinx.homeCombineMoviesTV") private var combineMoviesTV = true

    /// Section IDs in user-configured display order.
    private var orderedHomeSections: [String] {
        let stored = decodeHomeStringArray(homeSectionOrderJson)
        let defaults: [String] = combineMoviesTV
            ? ["continueWatching", "moviesAndTV", "otherVideos"]
            : ["continueWatching", "recentMovies", "recentTV", "otherVideos"]
        if stored.isEmpty { return defaults }
        let storedKnown = stored.filter { defaults.contains($0) }
        let missing = defaults.filter { !Set(stored).contains($0) }
        return storedKnown + missing
    }

    var body: some View {
        Group {
            if isAwaitingContent && !hasContent {
                fullscreenLoading
            } else if let error = errorMessage, !hasContent {
                PlinxErrorView(message: error) {
                    Task { await refreshContent() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                scrollContent
            }
        }
        .task { await viewModel.load() }
        .task(id: recentlyAddedSource) {
            // Libraries of servers that joined since the shell loaded them.
            try? await libraryStore.loadLibraries()
            guard !Task.isCancelled else { return }
            // Legacy Home library ids migrate once every enabled server's libraries are known.
            HomeLibrarySettingKeys.migrateStoredKeys(
                hiddenJSON: $homeHiddenIdsJson,
                orderJSON: $homeOrderJson,
                libraryStore: libraryStore,
                registry: registry
            )
            await recentlyAdded.sync(libraries: libraryStore.visibleLibraries, registry: registry)
        }
        .task(id: recentlyAddedRefreshKey) {
            // Changes made from the app (watched, deleted, refreshed) reload
            // their server once playback ends, grouped by server like `HomeViewModel`.
            guard !mainCoordinator.isPresentingPlayer else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await recentlyAdded.refreshChangedServers(registry: registry)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await viewModel.refreshPeriodically()
        }
        .onAppear {
            Task { await viewModel.refreshIfNeeded() }
        }
        .onChange(of: viewModel.contentRevisions) {
            viewModel.refreshAfterContentChanges()
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task {
                await viewModel.refreshIfNeeded()
                await recentlyAdded.refreshIfStale(registry: registry)
            }
        }
        .plinxRefreshable { await refreshContent() }
        #if os(tvOS)
        .onAppear {
            synchronizeHeroSelection()
        }
        .onChange(of: defaultHeroMedia.map(Self.mediaKey)) { _, _ in
            synchronizeHeroSelection()
        }
        .onChange(of: contentFocusRequest) { _, _ in
            requestContentFocus()
        }
        .onChange(of: homeRows.map { "\($0.id):\($0.hub.items.count)" }) { _, _ in
            guard focusedCard != nil || isContentFocusPending else { return }
            restoreContentFocusIfAvailable(forceTransfer: isContentFocusPending)
        }
        #endif
    }

    // MARK: - Loading state

    /// What the recently-added rows are built from: a change loads the libraries it adds and drops the others.
    private var recentlyAddedSource: RecentlyAddedSource {
        RecentlyAddedSource(
            libraries: libraryStore.visibleLibraries.map(\.identity),
            readyServers: registry.readyServers,
            policyRevision: ContentSafetyGate.shared.revision
        )
    }

    private var recentlyAddedRefreshKey: RecentlyAddedRefreshKey {
        RecentlyAddedRefreshKey(
            revisions: Dictionary(
                registry.connectedServices.map { ($0.identity, $0.watchStateRevision + $0.mediaRevision) },
                uniquingKeysWith: { first, _ in first }
            ),
            isPlayerPresented: mainCoordinator.isPresentingPlayer
        )
    }

    private var isAwaitingContent: Bool {
        viewModel.isLoading
            || recentlyAdded.isLoading
            || !recentlyAdded.hasSynced
            || libraryStore.isLoading
            || registry.isConnecting
    }

    private var hasContent: Bool {
        !homeRows.isEmpty
    }

    private var errorMessage: String? {
        if let message = viewModel.errorMessage {
            return message
        }
        guard recentlyAdded.hasFailed || libraryStore.loadFailed else { return nil }
        return String(localized: "home.error.unavailable")
    }

    // MARK: - Subviews

    private var fullscreenLoading: some View {
        PlinxBrandedLoadingView(context: .appTransition)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scrollContent: some View {
        #if os(tvOS)
        SharedTvBrowsePageLayout(
            heroMedia: selectedHeroMedia ?? defaultHeroMedia,
            showsFilters: false,
            heroMetrics: .home,
            navigationContent: {
                if let topContent {
                    topContent
                }
            },
            filterContent: {
                EmptyView()
            },
            rowsContent: { _ in
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(homeRows.enumerated()), id: \.element.id) { rowIndex, row in
                        hubRow(
                            row.hub,
                            layout: row.layout,
                            sectionKey: row.sectionKey,
                            rowIndex: rowIndex,
                            rowCount: homeRows.count
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, bottomContentPadding)
            }
        )
        .id(artworkRefreshToken)
        #else
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let topContent {
                    topContent
                }

                ForEach(Array(homeRows.enumerated()), id: \.element.id) { rowIndex, row in
                    hubRow(
                        row.hub,
                        layout: row.layout,
                        sectionKey: row.sectionKey,
                        rowIndex: rowIndex,
                        rowCount: homeRows.count
                    )
                }
            }
            .padding(.top, 8)
            .padding(.bottom, bottomContentPadding)
        }
        .id(artworkRefreshToken)
        #endif
    }

    private func refreshContent() async {
        let viewModel = viewModel
        let recentlyAdded = recentlyAdded
        let registry = registry
        async let home: Void = viewModel.reload()
        async let recent: Void = recentlyAdded.reload(registry: registry)
        _ = await (home, recent)
        artworkRefreshToken = UUID()
    }

    private var homeRows: [ShelfRow] {
        var rows: [ShelfRow] = []
        let groups = recentlyAddedRows

        for sectionId in orderedHomeSections {
            switch sectionId {
            case "continueWatching":
                rows.append(contentsOf: continueWatchingRows)
            case "moviesAndTV", "recentMovies", "recentTV", "otherVideos":
                rows.append(contentsOf: groups.filter { $0.sectionKey == sectionId && $0.hub.hasItems })
            default:
                break
            }
        }

        return rows
    }

    private var availableHeroMedia: [MediaItem] {
        homeRows.flatMap { $0.hub.items.compactMap(\.playableItem) }
    }

    private var defaultHeroMedia: MediaItem? {
        availableHeroMedia.first
    }

    /// Identifies a title across servers, for hero selection and focus memory.
    private static func mediaKey(_ media: MediaItem) -> String {
        HomeLibraryGrouping.itemKey(.playable(media))
    }

    #if os(tvOS)
    private func synchronizeHeroSelection() {
        let available = availableHeroMedia
        guard let selectedKey = HomeHeroSelection.resolvedMediaID(
            currentID: selectedHeroMedia.map(Self.mediaKey),
            availableIDs: available.map(Self.mediaKey)
        ), let media = available.first(where: { Self.mediaKey($0) == selectedKey }) else {
            selectedHeroMedia = nil
            return
        }

        selectedHeroMedia = media
    }

    private func selectHeroMedia(_ media: MediaItem) {
        selectedHeroMedia = media
        // Keep generic library cards in sync without allowing a previous
        // library focus to choose the Home hero when this screen returns.
        mediaFocusModel.focusedMedia = media
    }

    private func requestContentFocus() {
        isContentFocusPending = true
        restoreContentFocusIfAvailable(forceTransfer: true)
    }

    private func restoreContentFocusIfAvailable(forceTransfer: Bool = false) {
        let availableTargets = homeRows.enumerated().flatMap { rowIndex, row in
            row.hub.items.indices.map { itemIndex in
                HomeFocusTarget.card(row: rowIndex, item: itemIndex)
            }
        }
        let preferredTarget = tvFocusCoordinator.rememberedContentTarget(
            in: .home,
            availableIDs: homeRows.flatMap { $0.hub.items.map(HomeLibraryGrouping.itemKey) }
        ).flatMap(focusTarget(forItemKey:))
        guard let target = PlinxTVFocusCoordinator.resolvedContentID(
            currentID: focusedCard,
            availableIDs: availableTargets,
            preferredID: preferredTarget
        ) else {
            contentFocusGeneration &+= 1
            focusedCard = nil
            isContentFocusPending = false
            return
        }

        guard forceTransfer else {
            focusedCard = target
            return
        }

        // A hidden Home view can retain the same FocusState value while the
        // actual focus engine has moved to the persistent shell. Clear and
        // reassert on the next actor turn so every explicit Down request
        // performs a real transfer, even after returning from Library.
        contentFocusGeneration &+= 1
        let generation = contentFocusGeneration
        focusedCard = nil
        Task { @MainActor in
            await Task.yield()
            guard generation == contentFocusGeneration else { return }
            focusedCard = target
            isContentFocusPending = false
        }
    }

    private func focusTarget(forItemKey itemKey: String) -> HomeFocusTarget? {
        for (rowIndex, row) in homeRows.enumerated() {
            if let itemIndex = row.hub.items.firstIndex(where: { HomeLibraryGrouping.itemKey($0) == itemKey }) {
                return .card(row: rowIndex, item: itemIndex)
            }
        }
        return nil
    }
    #endif

    // MARK: - Rows

    enum CardLayout { case portrait, landscape }

    private struct ShelfRow: Identifiable {
        let id: String
        let hub: Hub
        let layout: CardLayout
        let sectionKey: String
    }

    private struct RecentlyAddedSource: Equatable {
        let libraries: [LibraryIdentity]
        let readyServers: Set<ServerIdentity>
        let policyRevision: Int
    }

    private struct RecentlyAddedRefreshKey: Equatable {
        let revisions: [ServerIdentity: Int]
        let isPlayerPresented: Bool
    }

    #if os(tvOS)
    private enum HomeFocusTarget: Hashable {
        case card(row: Int, item: Int)
    }
    #endif

    /// Continue Watching (and Next Up) from `HomeViewModel`, re-checked against the current policy.
    private var continueWatchingRows: [ShelfRow] {
        let gate = ContentSafetyGate.shared
        return HomeLibraryGrouping.continueWatchingRows(from: viewModel.rows).compactMap { row in
            let items = gate.filter(row.items)
            guard !items.isEmpty else { return nil }
            return ShelfRow(
                id: row.id,
                hub: Hub(id: row.id, title: row.title, items: items),
                layout: .landscape,
                sectionKey: row.sectionKey
            )
        }
    }

    // MARK: - Home library filtering & ordering

    private var recentlyAddedRows: [ShelfRow] {
        let gate = ContentSafetyGate.shared
        let catalogs = recentlyAdded.catalogs.map {
            LibraryCatalogResult(library: $0.library, items: gate.filter($0.items))
        }
        let rows = HomeRecentlyAddedProjection.rows(
            from: catalogs,
            hiddenLibraryIDs: Set(decodeHomeStringArray(homeHiddenIdsJson)),
            libraryOrder: decodeHomeStringArray(homeOrderJson),
            combineMoviesTV: combineMoviesTV
        )

        Self.logger.debug(
            "Recently-added rows=\(rows.count, privacy: .public) items=\(rows.reduce(0) { $0 + $1.items.count }, privacy: .public)"
        )

        return rows.map { row in
            ShelfRow(
                id: row.id,
                hub: Hub(id: row.id, title: row.title, items: row.items),
                layout: row.layout == .landscape ? .landscape : .portrait,
                sectionKey: row.sectionKey
            )
        }
    }

    // MARK: - Hub row

    private func hubRow(_ hub: Hub, layout: CardLayout, sectionKey: String, rowIndex: Int, rowCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hub.title)
                .font(sectionTitleFont)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .accessibilityIdentifier("home.section.\(sectionKey)")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: cardSpacing) {
                    ForEach(Array(hub.items.enumerated()), id: \.element.homeItemKey) { index, item in
                        mediaCardButton(
                            item,
                            layout: layout,
                            sectionKey: sectionKey,
                            rowIndex: rowIndex,
                            rowCount: rowCount,
                            index: index
                        )
                    }
                }
                .padding(.vertical, cardFocusPadding)
                .padding(.horizontal, 20)
            }
            #if os(tvOS)
            .scrollClipDisabled()
            #endif
        }
        .accessibilityIdentifier("home.hub.\(sectionKey)")
    }

    @ViewBuilder
    private func mediaCardButton(
        _ item: MediaDisplayItem,
        layout: CardLayout,
        sectionKey: String,
        rowIndex: Int,
        rowCount: Int,
        index: Int
    ) -> some View {
        let card = mediaCard(item, layout: layout, sectionKey: sectionKey, index: index)

        #if os(tvOS)
        Button {
            onSelectMedia(item)
        } label: {
            card
        }
            .buttonStyle(PlinkButtonStyle())
            .focusEffectDisabled()
            .focused($focusedCard, equals: .card(row: rowIndex, item: index))
            .onChange(of: focusedCard) { _, newTarget in
                guard newTarget == .card(row: rowIndex, item: index),
                      let playableItem = item.playableItem
                else { return }
                selectHeroMedia(playableItem)
                tvFocusCoordinator.rememberContentTarget(item.homeItemKey, in: .home)
            }
            .plinxQuickActionLongPress { onLongPressMedia(item) }
            .onMoveCommand { direction in
                handleMoveCommand(direction, fromRow: rowIndex, rowCount: rowCount)
            }
        #else
        card.plinxMediaCardInteraction(
            onTap: { onSelectMedia(item) },
            onLongPress: { onLongPressMedia(item) }
        )
        #endif
    }

    #if os(tvOS)
    private func handleMoveCommand(_ direction: MoveCommandDirection, fromRow rowIndex: Int, rowCount: Int) {
        let route: HomeVerticalFocusRoute
        switch direction {
        case .up:
            route = HomeVerticalFocusRouting.nextRoute(direction: .up, fromRow: rowIndex, rowCount: rowCount)
        case .down:
            route = HomeVerticalFocusRouting.nextRoute(direction: .down, fromRow: rowIndex, rowCount: rowCount)
        default:
            return
        }

        switch route {
        case .navigation:
            contentFocusGeneration &+= 1
            onRequestHomeNavigationFocus()
        case let .card(row, item):
            focusedCard = .card(row: row, item: item)
        case .unchanged:
            break
        }
    }
    #endif

    private func mediaCard(_ item: MediaDisplayItem, layout: CardLayout, sectionKey: String, index: Int) -> some View {
        let isLandscape = layout == .landscape
        let cardWidth: CGFloat = isLandscape ? landscapeCardWidth : portraitCardWidth
        let ratio: CGFloat = isLandscape ? 16.0 / 9.0 : 2.0 / 3.0
        let isContinueWatching = sectionKey == "continueWatching"
        let watched = isItemWatched(item)
        let artworkKind = ArtworkSelectionPolicy.artworkKind(
            forHomeSection: sectionKey,
            item: item,
            isLandscape: isLandscape
        )
        let imageViewModel = registry.services(for: item.server).map {
            MediaImageViewModel(services: $0, artworkKind: artworkKind, media: item)
        }

        return HomeMediaCardBody(
            item: item,
            sectionKey: sectionKey,
            index: index,
            cardWidth: cardWidth,
            ratio: ratio,
            isContinueWatching: isContinueWatching,
            watched: watched,
            imageViewModel: imageViewModel
        )
    }

    private var sectionTitleFont: Font {
        #if os(tvOS)
        .system(size: 30, weight: .bold, design: .rounded)
        #else
        .title3.bold()
        #endif
    }

    private var cardSpacing: CGFloat {
        #if os(tvOS)
        24
        #else
        12
        #endif
    }

    private var portraitCardWidth: CGFloat {
        #if os(tvOS)
        170
        #else
        110
        #endif
    }

    private var landscapeCardWidth: CGFloat {
        #if os(tvOS)
        300
        #else
        200
        #endif
    }

    private var cardFocusPadding: CGFloat {
        #if os(tvOS)
        10
        #else
        0
        #endif
    }

    private var bottomContentPadding: CGFloat {
        #if os(tvOS)
        24
        #else
        120
        #endif
    }
}

private extension MediaDisplayItem {
    /// Row identity across servers, whose item ids can repeat.
    var homeItemKey: String {
        HomeLibraryGrouping.itemKey(self)
    }
}
