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

struct PlinxHomeView: View {
    private static let logger = Logger(subsystem: "com.plinx.app", category: "home")

    @State var viewModel: SafeHomeViewModel
    var topContent: AnyView? = nil
    var onSelectMedia: (MediaDisplayItem) -> Void
    var onLongPressMedia: (MediaDisplayItem) -> Void = { _ in }
    var onRequestHomeNavigationFocus: () -> Void = {}
    var contentFocusRequest: Int = 0
    /// Returns whether a given display item should show as watched.
    /// Injected by parent to reflect optimistic local overrides.
    var isItemWatched: (MediaDisplayItem) -> Bool = { $0.isFullyWatched }

    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(\.safetyPolicy) private var safetyPolicy
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
            if viewModel.isLoading && !viewModel.hasContent {
                fullscreenLoading
            } else if let error = viewModel.errorMessage, !viewModel.hasContent {
                PlinxErrorView(message: error) {
                    Task { await viewModel.reload() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                scrollContent
            }
        }
        .task { await viewModel.load() }
        .plinxRefreshable { await refreshContent() }
        .onChange(of: safetyPolicy) { _, newPolicy in
            // When the parent updates the safety policy (max rating changed,
            // excludeUnrated toggled) re-filter cached hub data immediately
            // without a full network reload.
            viewModel.updatePolicy(newPolicy)
        }
        #if os(tvOS)
        .onAppear {
            synchronizeHeroSelection()
        }
        .onChange(of: defaultHeroMedia?.id) { _, _ in
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
        await viewModel.reload()
        artworkRefreshToken = UUID()
    }

    private var homeRows: [HomeRow] {
        var rows: [HomeRow] = []
        let groups = displayedGroups

        for sectionId in orderedHomeSections {
            switch sectionId {
            case "continueWatching":
                rows.append(contentsOf: HomeLibraryGrouping.continueWatchingRows(from: viewModel.continueWatching).map {
                    HomeRow(
                        id: $0.id,
                        hub: Hub(id: $0.id, title: $0.title, items: $0.items),
                        layout: .landscape,
                        sectionKey: $0.sectionKey
                    )
                })
            case "moviesAndTV":
                rows.append(contentsOf: groups.filter { $0.sectionKey == "moviesAndTV" && $0.hub.hasItems }.map {
                    HomeRow(id: $0.id, hub: $0.hub, layout: $0.layout, sectionKey: "moviesAndTV")
                })
            case "recentMovies":
                rows.append(contentsOf: groups.filter { $0.sectionKey == "recentMovies" && $0.hub.hasItems }.map {
                    HomeRow(id: $0.id, hub: $0.hub, layout: $0.layout, sectionKey: "recentMovies")
                })
            case "recentTV":
                rows.append(contentsOf: groups.filter { $0.sectionKey == "recentTV" && $0.hub.hasItems }.map {
                    HomeRow(id: $0.id, hub: $0.hub, layout: $0.layout, sectionKey: "recentTV")
                })
            case "otherVideos":
                rows.append(contentsOf: groups.filter { $0.sectionKey == "otherVideos" && $0.hub.hasItems }.map {
                    HomeRow(id: $0.id, hub: $0.hub, layout: $0.layout, sectionKey: "otherVideos")
                })
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

    #if os(tvOS)
    private func synchronizeHeroSelection() {
        let availableIDs = availableHeroMedia.map(\.id)
        guard let selectedID = HomeHeroSelection.resolvedMediaID(
            currentID: selectedHeroMedia?.id,
            availableIDs: availableIDs
        ), let media = availableHeroMedia.first(where: { $0.id == selectedID }) else {
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
            availableIDs: homeRows.flatMap { $0.hub.items.map(\.id) }
        ).flatMap(focusTarget(forMediaID:))
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

    private func focusTarget(forMediaID mediaID: String) -> HomeFocusTarget? {
        for (rowIndex, row) in homeRows.enumerated() {
            if let itemIndex = row.hub.items.firstIndex(where: { $0.id == mediaID }) {
                return .card(row: rowIndex, item: itemIndex)
            }
        }
        return nil
    }
    #endif

    // MARK: - Hub layout groups

    enum CardLayout { case portrait, landscape }

    private struct HubGroup: Identifiable {
        let id: String
        let hub: Hub
        let layout: CardLayout
        let sectionKey: String
    }

    private struct HomeRow: Identifiable {
        let id: String
        let hub: Hub
        let layout: CardLayout
        let sectionKey: String
    }

    #if os(tvOS)
    private enum HomeFocusTarget: Hashable {
        case card(row: Int, item: Int)
    }
    #endif

    // MARK: - Home library filtering & ordering

    private var displayedGroups: [HubGroup] {
        let hiddenIds = decodeHomeStringArray(homeHiddenIdsJson)
        let order = decodeHomeStringArray(homeOrderJson)
        let rows = HomeRecentlyAddedProjection.rows(
            from: viewModel.recentCatalogs,
            hiddenLibraryIDs: Set(hiddenIds),
            libraryOrder: order,
            combineMoviesTV: combineMoviesTV
        )

        Self.logger.debug(
            "Recently-added rows=\(rows.count, privacy: .public) items=\(rows.reduce(0) { $0 + $1.items.count }, privacy: .public)"
        )

        return rows.map { row in
            let hub = Hub(id: row.id, title: row.title, items: row.items)
            return HubGroup(
                id: row.id,
                hub: hub,
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
                    ForEach(Array(hub.items.enumerated()), id: \.element.id) { index, item in
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
                tvFocusCoordinator.rememberContentTarget(item.id, in: .home)
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
        let imageViewModel = MediaImageViewModel(
            context: plexApiContext,
            artworkKind: artworkKind,
            media: item
        )

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
