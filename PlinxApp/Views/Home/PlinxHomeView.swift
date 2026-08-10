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
    #endif

    // Plinx-specific home screen settings (separate from Library-tab visibility)
    @AppStorage("plinx.homeHiddenLibraryIds") private var homeHiddenIdsJson = "[]"
    @AppStorage("plinx.homeLibraryOrder") private var homeOrderJson = "[]"
    @AppStorage("plinx.homeSectionOrder") private var homeSectionOrderJson = "[]"
    @AppStorage("plinx.homeCombineMoviesTV") private var combineMoviesTV = true

    /// Section IDs in user-configured display order.
    private var orderedHomeSections: [String] {
        let stored = decodeStringArray(homeSectionOrderJson)
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
            restoreContentFocusIfAvailable()
        }
        .onChange(of: homeRows.map { "\($0.id):\($0.hub.items.count)" }) { _, _ in
            guard focusedCard != nil else { return }
            restoreContentFocusIfAvailable()
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
                LazyVStack(alignment: .leading, spacing: 24) {
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

    private func restoreContentFocusIfAvailable() {
        let availableTargets = homeRows.enumerated().flatMap { rowIndex, row in
            row.hub.items.indices.map { itemIndex in
                HomeFocusTarget.card(row: rowIndex, item: itemIndex)
            }
        }
        let preferredTarget = tvFocusCoordinator.rememberedContentTarget(
            in: .home,
            availableIDs: homeRows.flatMap { $0.hub.items.map(\.id) }
        ).flatMap(focusTarget(forMediaID:))
        focusedCard = PlinxTVFocusCoordinator.resolvedContentID(
            currentID: focusedCard,
            availableIDs: availableTargets,
            preferredID: preferredTarget
        )
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
        let hiddenIds = decodeStringArray(homeHiddenIdsJson)
        let order = decodeStringArray(homeOrderJson)
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
        VStack(alignment: .leading, spacing: 10) {
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
        card
            .focused($focusedCard, equals: .card(row: rowIndex, item: index))
            .focusable()
            .focusEffectDisabled()
            .onChange(of: focusedCard) { _, newTarget in
                guard newTarget == .card(row: rowIndex, item: index),
                      let playableItem = item.playableItem
                else { return }
                selectHeroMedia(playableItem)
                tvFocusCoordinator.rememberContentTarget(item.id, in: .home)
            }
            .onTapGesture { onSelectMedia(item) }
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
        .system(size: 22, weight: .bold, design: .default)
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
        24
        #else
        0
        #endif
    }

    private var bottomContentPadding: CGFloat {
        #if os(tvOS)
        36
        #else
        120
        #endif
    }
}

/// Gives media cards one deterministic touch contract. A completed long press
/// wins over a tap, so opening quick actions never also starts playback or
/// navigation when the finger is released.
private struct PlinxMediaCardInteractionModifier: ViewModifier {
    let onTap: () -> Void
    let onLongPress: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(tvOS)
        content
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
        #else
        content
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.5, maximumDistance: 24)
                    .exclusively(before: TapGesture())
                    .onEnded { value in
                        switch value {
                        case .first:
                            onLongPress()
                        case .second:
                            onTap()
                        }
                    },
                including: .gesture
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
        #endif
    }
}

extension View {
    func plinxMediaCardInteraction(
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void
    ) -> some View {
        modifier(PlinxMediaCardInteractionModifier(onTap: onTap, onLongPress: onLongPress))
    }

    /// Use when an existing reusable card owns its normal Button action. The
    /// high-priority recognizer prevents that Button from winning a long press.
    @ViewBuilder
    func plinxQuickActionLongPress(_ action: @escaping () -> Void) -> some View {
        #if os(tvOS)
        self
        #else
        highPriorityGesture(
            LongPressGesture(minimumDuration: 0.5, maximumDistance: 24)
                .onEnded { _ in action() }
        )
        #endif
    }
}

private struct HomeMediaCardBody: View {
    let item: MediaDisplayItem
    let sectionKey: String
    let index: Int
    let cardWidth: CGFloat
    let ratio: CGFloat
    let isContinueWatching: Bool
    let watched: Bool
    let imageViewModel: MediaImageViewModel

    @Environment(\.isFocused) private var isFocused

    private var thumbHeight: CGFloat { cardWidth / ratio }

    private var focusHaloInset: CGFloat {
        #if os(tvOS)
        24
        #else
        0
        #endif
    }

    private var artworkCornerRadius: CGFloat {
        #if os(tvOS)
        18
        #else
        11
        #endif
    }

    private var titleFont: Font {
        #if os(tvOS)
        .subheadline.bold()
        #else
        .caption.bold()
        #endif
    }

    private var subtitleFont: Font {
        #if os(tvOS)
        .caption
        #else
        .caption2
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                    MediaImageView(
                        viewModel: imageViewModel
                    )
                    .frame(width: cardWidth, height: thumbHeight)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if !isContinueWatching && watched {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.accentColor)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 24, height: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.black.opacity(0.3), lineWidth: 1)
                            )
                            .padding(8)
                        }
                    }
                    .accessibilityIdentifier("home.thumbnail.\(sectionKey).\(index)")

                    if let pct = item.viewProgressPercentage, pct > 0 {
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.30))
                                .frame(width: cardWidth)
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: cardWidth * CGFloat(min(pct / 100.0, 1.0)))
                        }
                        .frame(width: cardWidth, height: 8)
                        .clipShape(RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous)
                                .stroke(Color.black.opacity(0.7), lineWidth: 1)
                        }
                    }
            }
            .frame(width: cardWidth, height: thumbHeight)
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .overlay {
                RoundedRectangle(
                    cornerRadius: isFocused ? artworkCornerRadius * 1.08 : artworkCornerRadius,
                    style: .continuous
                )
                .stroke(Color.accentColor, lineWidth: isFocused ? 4 : 0)
                .scaleEffect(isFocused ? 1.08 : 1.0)
            }
            .shadow(color: isFocused ? Color.accentColor.opacity(0.58) : .clear, radius: isFocused ? 10 : 0)
            .shadow(color: isFocused ? Color.accentColor.opacity(0.22) : .clear, radius: isFocused ? 18 : 0)
            .frame(width: cardWidth + (focusHaloInset * 2), height: thumbHeight + (focusHaloInset * 2))

            Text(item.primaryLabel)
                .font(titleFont)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: cardWidth, alignment: .leading)
                .padding(.leading, focusHaloInset)

            if let sub = item.secondaryLabel {
                Text(sub)
                    .font(subtitleFont)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .frame(width: cardWidth, alignment: .leading)
                    .padding(.leading, focusHaloInset)
            }
        }
        .frame(width: cardWidth + (focusHaloInset * 2), alignment: .leading)
        #if os(tvOS)
        .focusEffectDisabled()
        #endif
        .accessibilityIdentifier("home.card.\(sectionKey).\(index)")
    }
}

// MARK: - JSON helpers (file-private)

private func decodeStringArray(_ json: String) -> [String] {
    guard let data = json.data(using: .utf8),
          let arr = try? JSONDecoder().decode([String].self, from: data)
    else { return [] }
    return arr
}

#if os(tvOS)

struct TvBrowseHeroMetrics {
    let heightRatio: CGFloat
    let leadingSafeAreaReduction: CGFloat
    let contentHorizontalPadding: CGFloat
    let contentTopPadding: CGFloat
    let metadataBottomPadding: CGFloat

    static let `default` = TvBrowseHeroMetrics(
        heightRatio: 0.408,
        leadingSafeAreaReduction: 0,
        contentHorizontalPadding: 4,
        contentTopPadding: 1,
        metadataBottomPadding: 8
    )

    static let home = TvBrowseHeroMetrics(
        heightRatio: 0.408,
        leadingSafeAreaReduction: 0.5,
        contentHorizontalPadding: 4,
        contentTopPadding: 0,
        metadataBottomPadding: 8
    )
}

struct SharedTvBrowsePageLayout<NavigationContent: View, FilterContent: View, RowsContent: View>: View {
    let heroMedia: MediaItem?
    let showsFilters: Bool
    var heroMetrics: TvBrowseHeroMetrics = .default
    @ViewBuilder let navigationContent: () -> NavigationContent
    @ViewBuilder let filterContent: () -> FilterContent
    @ViewBuilder let rowsContent: (ScrollViewProxy) -> RowsContent

    var body: some View {
        ScrollViewReader { scrollProxy in
            GeometryReader { proxy in
                let heroHeight = proxy.size.height * heroMetrics.heightRatio
                let rowsHeight = max(proxy.size.height - heroHeight, 0)
                let leadingShift = -(proxy.safeAreaInsets.leading * heroMetrics.leadingSafeAreaReduction)

                VStack(spacing: 0) {
                    heroSection(
                        availableWidth: proxy.size.width
                    )
                        .frame(height: heroHeight)
                        .background(Color.appBackground)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if showsFilters {
                                filterContent()
                                    .padding(.top, 6)
                            }

                            rowsContent(scrollProxy)
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 22)
                        .frame(minHeight: rowsHeight, alignment: .top)
                    }
                    .clipped()
                    .frame(height: rowsHeight)
                }
                .padding(.leading, leadingShift)
                .frame(width: proxy.size.width - leadingShift, alignment: .leading)
                .background(Color.appBackground.ignoresSafeArea())
            }
        }
    }

    private func heroSection(availableWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if let heroMedia {
                TvPinnedHeroBackdrop(media: heroMedia)
            } else {
                Color.appBackground
            }

            VStack(alignment: .leading, spacing: 8) {
                navigationContent()

                Spacer(minLength: 0)

                if let heroMedia {
                    TvHeroMetadataPanel(media: heroMedia)
                        .frame(maxWidth: availableWidth * 0.54, alignment: .leading)
                    .padding(.bottom, heroMetrics.metadataBottomPadding)
                }
            }
            .padding(.horizontal, heroMetrics.contentHorizontalPadding)
            .padding(.top, heroMetrics.contentTopPadding)
        }
        .clipped()
    }
}

struct TvPillButtonStyle: ButtonStyle {
    let isSelected: Bool
    let cornerRadius: CGFloat

    init(isSelected: Bool = false, cornerRadius: CGFloat = 16) {
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
    }

    func makeBody(configuration: Configuration) -> some View {
        TvPillButtonBody(configuration: configuration, isSelected: isSelected, cornerRadius: cornerRadius)
    }
}

private struct TvPillButtonBody: View {
    let configuration: TvPillButtonStyle.Configuration
    let isSelected: Bool
    let cornerRadius: CGFloat

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: isFocused ? 2.5 : 1.2)
            )
            .shadow(color: shadowColor, radius: isFocused ? 18 : 6)
            .scaleEffect(isFocused ? 1.08 : (isSelected ? 1.03 : 1.0))
            .animation(.easeOut(duration: 0.14), value: isFocused)
            .animation(.easeOut(duration: 0.14), value: isSelected)
    }

    private var foregroundColor: Color {
        if isSelected {
            return .white
        }
        return isFocused ? .white : .white.opacity(0.86)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(isFocused ? 0.82 : 0.68)
        }
        return Color.white.opacity(isFocused ? 0.12 : 0.08)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(isFocused ? 1.0 : 0.78)
        }
        return isFocused ? Color.accentColor.opacity(0.94) : Color.white.opacity(0.22)
    }

    private var shadowColor: Color {
        (isFocused || isSelected) ? Color.accentColor.opacity(isFocused ? 0.68 : 0.32) : .clear
    }
}

private struct TvHeroExternalRating: Identifiable, Hashable {
    let id: String
    let provider: String
    let value: String
    let isAudience: Bool
}

private struct TvHeroMetadataPanel: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    let media: MediaItem

    @State private var externalRatings: [TvHeroExternalRating] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataAndRatingsRow

            if let summary = media.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .lineSpacing(1.2)
                    .foregroundStyle(.brandSecondary)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.black.opacity(0.28))
                    .blur(radius: 10)
                    .padding(-5)

                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(0.34))
            }
        )
        .task(id: media.id) {
            await loadHeroMetadata()
        }
    }

    @ViewBuilder
    private var metadataAndRatingsRow: some View {
        if !metadataItems.isEmpty || !externalRatings.isEmpty || media.rating != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(metadataItems, id: \.self) { item in
                        Text(item)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.brandSecondary)
                    }

                    ForEach(externalRatings) { rating in
                        ratingBadge(rating)
                    }

                    if externalRatings.isEmpty, let score = media.rating {
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill")
                            Text(String(format: "%.1f", score))
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.brandSecondary)
                    }
                }
            }
        }
    }

    private func ratingBadge(_ rating: TvHeroExternalRating) -> some View {
        HStack(spacing: 5) {
            ratingProviderIconView(rating)
            Text(rating.value)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var metadataItems: [String] {
        var items: [String] = []
        if let tertiary = media.tertiaryLabel {
            items.append(tertiary)
        }
        if let year = media.year {
            items.append(String(year))
        }
        if let duration = media.duration {
            items.append(duration.mediaDurationText())
        }
        if let contentRating = media.contentRating {
            items.append(contentRating)
        }
        return items
    }

    private func loadHeroMetadata() async {
        externalRatings = []

        do {
            let metadataRepository = try MetadataRepository(context: plexApiContext)
            let response = try await metadataRepository.getMetadata(ratingKey: media.metadataRatingKey)
            guard let item = response.mediaContainer.metadata?.first else { return }

            externalRatings = resolveExternalRatings(from: item)
        } catch {
            externalRatings = []
        }
    }

    private func resolveExternalRatings(from item: PlexItem) -> [TvHeroExternalRating] {
        var ratingsByID: [String: TvHeroExternalRating] = [:]

        func addRating(provider: String, value: Double, isAudience: Bool) {
            guard isSupportedProvider(provider) else { return }
            let providerID = normalizedProvider(provider)
            let id = "\(providerID)-\(isAudience ? "audience" : "critic")"
            guard ratingsByID[id] == nil else { return }
            ratingsByID[id] = TvHeroExternalRating(
                id: id,
                provider: provider,
                value: formattedRatingValue(value, provider: provider),
                isAudience: isAudience
            )
        }

        for rating in item.ratings ?? [] {
            let value = rating.value
            guard let provider = providerName(from: rating.image) ?? providerName(from: rating.type) else { continue }
            let isAudience = isAudienceRatingSource(rating.image) || isAudienceRatingSource(rating.type)
            addRating(provider: provider, value: value, isAudience: isAudience)
        }

        if let value = item.rating,
           let provider = providerName(from: item.ratingImage)
        {
            addRating(provider: provider, value: value, isAudience: false)
        }

        if let value = item.audienceRating,
           let provider = providerName(from: item.audienceRatingImage)
        {
            addRating(provider: provider, value: value, isAudience: true)
        }

        return ratingsByID.values.sorted { lhs, rhs in
            let lhsPriority = ratingSortPriority(lhs)
            let rhsPriority = ratingSortPriority(rhs)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            if lhs.isAudience != rhs.isAudience { return lhs.isAudience == false }
            return lhs.provider < rhs.provider
        }
    }

    @ViewBuilder
    private func ratingProviderIconView(_ rating: TvHeroExternalRating) -> some View {
        let assetName = ratingIconAssetName(rating)
        if UIImage(named: assetName) != nil {
            Image(assetName)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: ratingProviderSFSymbol(rating))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    private func ratingIconAssetName(_ rating: TvHeroExternalRating) -> String {
        let norm = normalizedRatingProvider(rating.provider)
        if (norm == "rottentomatoes" || norm == "rt") && rating.isAudience {
            return "rating.rt.audience"
        }
        switch norm {
        case "imdb": return "rating.imdb"
        case "rottentomatoes", "rt": return "rating.rt"
        case "tmdb", "themoviedatabase", "themoviedb": return "rating.tmdb"
        default: return "rating.\(norm)"
        }
    }

    private func ratingProviderSFSymbol(_ rating: TvHeroExternalRating) -> String {
        let norm = normalizedRatingProvider(rating.provider)
        if (norm == "rottentomatoes" || norm == "rt") && rating.isAudience {
            return "popcorn.fill"
        }
        switch norm {
        case "imdb": return "star.fill"
        case "rottentomatoes", "rt": return "circle.dotted.circle"
        case "tmdb", "themoviedatabase", "themoviedb": return "movieclapper.fill"
        case "tvdb": return "tv.fill"
        default: return "chart.bar.fill"
        }
    }

    private func normalizedRatingProvider(_ provider: String) -> String {
        provider
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private func providerName(from imageIdentifier: String?) -> String? {
        guard let imageIdentifier else { return nil }
        let value = imageIdentifier.lowercased()
        if value.contains("imdb") { return "IMDb" }
        if value.contains("rotten") || value.contains("tomato") || value == "rt" { return "Rotten Tomatoes" }
        if value.contains("tvdb") || value.contains("thetvdb") { return "TVDB" }
        if value.contains("tmdb") || value.contains("themoviedb") { return "TMDB" }
        return nil
    }

    private func isAudienceRatingSource(_ source: String?) -> Bool {
        guard let source else { return false }
        let value = source.lowercased()
        return value.contains("audience") || value.contains("user") || value.contains("popcorn")
    }

    private func normalizedProvider(_ provider: String) -> String {
        provider
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private func isSupportedProvider(_ provider: String) -> Bool {
        switch normalizedProvider(provider) {
        case "imdb", "rottentomatoes", "rt", "tmdb", "themoviedatabase", "themoviedb", "tvdb":
            return true
        default:
            return false
        }
    }

    private func ratingSortPriority(_ rating: TvHeroExternalRating) -> Int {
        let provider = normalizedProvider(rating.provider)
        switch provider {
        case "rottentomatoes", "rt": return rating.isAudience ? 1 : 0
        case "imdb": return 2
        case "tmdb", "themoviedatabase", "themoviedb": return 3
        case "tvdb": return 4
        default: return 9
        }
    }

    private func formattedRatingValue(_ rawValue: Double, provider: String) -> String {
        let providerID = normalizedProvider(provider)
        if providerID == "rottentomatoes" || providerID == "rt" {
            let percentage = rawValue <= 10 ? rawValue * 10 : rawValue
            return "\(Int(percentage.rounded()))%"
        }

        if providerID == "imdb" {
            return String(format: "%.1f", rawValue)
        }

        return String(format: "%.1f", rawValue)
    }
}

private struct TvHeroIdentityView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    let media: MediaItem

    @State private var logoURL: URL?

    var body: some View {
        Group {
            if let logoURL {
                AsyncImage(url: logoURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                    } else {
                        fallbackTitle
                    }
                }
            } else {
                fallbackTitle
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: media.id) {
            await loadLogo()
        }
    }

    private var fallbackTitle: some View {
        Text(media.primaryLabel)
            .font(.system(size: 72, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.55)
    }

    private func loadLogo() async {
        logoURL = nil
        do {
            let metadataRepository = try MetadataRepository(context: plexApiContext)
            let response = try await metadataRepository.getMetadata(ratingKey: media.metadataRatingKey)
            guard let item = response.mediaContainer.metadata?.first else { return }
            guard let imageRepository = try? ImageRepository(context: plexApiContext) else { return }
            guard let logoPath = item.images?.first(where: { image in
                image.type.localizedCaseInsensitiveContains("logo")
            })?.url.path else { return }

            logoURL = imageRepository.transcodeImageURL(path: logoPath, width: 1800, height: 700)
        } catch {
            logoURL = nil
        }
    }
}

private struct TvPinnedHeroBackdrop: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    let media: MediaItem

    @State private var imageURL: URL?
    @State private var displayedLogoURL: URL?
    @State private var displayedTitle: String = ""
    @State private var loadedIdentityForMediaID: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.appBackground

                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .empty:
                            Color.appBackground
                        case .failure:
                            Color.appBackground
                        @unknown default:
                            Color.appBackground
                        }
                    }
                    .frame(width: (proxy.size.width * 0.62) + 96, height: proxy.size.height)
                    .clipped()
                    .mask(TvPinnedHeroImageMask())
                    .offset(x: 48)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                LinearGradient(
                    stops: [
                        .init(color: Color.appBackground, location: 0.0),
                        .init(color: Color.appBackground.opacity(0.96), location: 0.28),
                        .init(color: .clear, location: 0.64),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                heroIdentityOverlay
                    .frame(width: proxy.size.width * 0.34, alignment: .trailing)
                    .padding(.trailing, 26)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .task(id: media.id) {
                await loadImage()
                await loadIdentityIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var heroIdentityOverlay: some View {
        Group {
            if let displayedLogoURL {
                AsyncImage(url: displayedLogoURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 185)
                    } else {
                        fallbackIdentityText
                    }
                }
            } else {
                fallbackIdentityText
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .shadow(color: .black.opacity(0.58), radius: 16, y: 6)
    }

    private var fallbackIdentityText: some View {
        Text(displayedTitle.isEmpty ? media.primaryLabel : displayedTitle)
            .font(.system(size: 54, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.55)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func loadIdentityIfNeeded() async {
        guard loadedIdentityForMediaID != media.id else { return }

        do {
            let metadataRepository = try MetadataRepository(context: plexApiContext)
            let response = try await metadataRepository.getMetadata(ratingKey: media.metadataRatingKey)
            guard let item = response.mediaContainer.metadata?.first else { return }

            let imageRepository = try? ImageRepository(context: plexApiContext)
            let resolvedLogoURL: URL? = item.images?.first(where: { image in
                image.type.localizedCaseInsensitiveContains("logo")
            }).flatMap { image in
                imageRepository?.transcodeImageURL(path: image.url.path, width: 1800, height: 700)
            }

            await MainActor.run {
                // Keep the previous identity visible until the next one is fully resolved.
                if let resolvedLogoURL {
                    displayedLogoURL = resolvedLogoURL
                    displayedTitle = media.primaryLabel
                } else {
                    displayedLogoURL = nil
                    displayedTitle = media.primaryLabel
                }
                loadedIdentityForMediaID = media.id
            }
        } catch {
            await MainActor.run {
                displayedLogoURL = nil
                displayedTitle = media.primaryLabel
                loadedIdentityForMediaID = media.id
            }
        }
    }

    private func loadImage() async {
        let path = media.grandparentArtPath
            ?? media.artPath
            ?? media.grandparentThumbPath
            ?? media.parentThumbPath
            ?? media.thumbPath

        guard let path else {
            imageURL = nil
            return
        }

        do {
            let imageRepository = try ImageRepository(context: plexApiContext)
            imageURL = imageRepository.transcodeImageURL(
                path: path,
                width: 3840,
                height: 2160,
                minSize: 1,
                upscale: 1
            )
        } catch {
            imageURL = nil
        }
    }
}

private struct TvPinnedHeroImageMask: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.18),
                .init(color: .black, location: 1.0),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.72),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

#endif
