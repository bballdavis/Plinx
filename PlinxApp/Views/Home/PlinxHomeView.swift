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
#endif

struct PlinxHomeView: View {
    private static let logger = Logger(subsystem: "com.plinx.app", category: "home")

    @State var viewModel: SafeHomeViewModel
    var topContent: AnyView? = nil
    var onSelectMedia: (MediaDisplayItem) -> Void
    var onLongPressMedia: (MediaDisplayItem) -> Void = { _ in }
    var onRequestHomeNavigationFocus: () -> Void = {}
    /// Returns whether a given display item should show as watched.
    /// Injected by parent to reflect optimistic local overrides.
    var isItemWatched: (MediaDisplayItem) -> Bool = { $0.isFullyWatched }

    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(\.safetyPolicy) private var safetyPolicy
    @State private var artworkRefreshToken = UUID()
    #if os(tvOS)
    @Environment(MediaFocusModel.self) private var mediaFocusModel
    @FocusState private var focusedCard: HomeFocusTarget?
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
        .refreshable { await refreshContent() }
        .onChange(of: safetyPolicy) { _, newPolicy in
            // When the parent updates the safety policy (max rating changed,
            // excludeUnrated toggled) re-filter cached hub data immediately
            // without a full network reload.
            viewModel.updatePolicy(newPolicy)
        }
        #if os(tvOS)
        .onAppear {
            updateInitialHeroFocus()
        }
        .onChange(of: defaultHeroMedia?.id) { _, _ in
            updateInitialHeroFocus()
        }
        #endif
    }

    // MARK: - Subviews

    private var fullscreenLoading: some View {
        PlinxBrandedLoadingView(
            titleKey: "home.loading",
            preferredLogoAssetName: "LogoStackedFullWhite",
            showsProgressView: true,
            fillsBackground: true
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scrollContent: some View {
        #if os(tvOS)
        SharedTvBrowsePageLayout(
            heroMedia: mediaFocusModel.focusedMedia ?? defaultHeroMedia,
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
                rows.append(contentsOf: moviesTVGroups.filter { $0.hub.hasItems }.map {
                    HomeRow(id: $0.id, hub: $0.hub, layout: $0.layout, sectionKey: "moviesAndTV")
                })
            case "recentMovies":
                rows.append(contentsOf: recentMoviesGroups.filter { $0.hub.hasItems }.map {
                    HomeRow(id: $0.id, hub: $0.hub, layout: $0.layout, sectionKey: "recentMovies")
                })
            case "recentTV":
                rows.append(contentsOf: recentTVGroups.filter { $0.hub.hasItems }.map {
                    HomeRow(id: $0.id, hub: $0.hub, layout: $0.layout, sectionKey: "recentTV")
                })
            case "otherVideos":
                rows.append(contentsOf: otherVideoGroups.filter { $0.hub.hasItems }.map {
                    HomeRow(id: $0.id, hub: $0.hub, layout: $0.layout, sectionKey: "otherVideos")
                })
            default:
                break
            }
        }

        return rows
    }

    private var defaultHeroMedia: MediaItem? {
        for row in homeRows where row.hub.hasItems {
            if let item = row.hub.items.compactMap(\.playableItem).first {
                return item
            }
        }
        return nil
    }

    #if os(tvOS)
    private func updateInitialHeroFocus() {
        guard mediaFocusModel.focusedMedia == nil, let defaultHeroMedia else { return }
        mediaFocusModel.focusedMedia = defaultHeroMedia
    }
    #endif

    // MARK: - Hub layout groups

    enum CardLayout { case portrait, landscape }

    private struct HubGroup: Identifiable {
        let id: String
        let hub: Hub
        let layout: CardLayout
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
        let libraries = libraryStore.libraries
        let recentlyAddedPrefix = NSLocalizedString("home.recentlyAdded.prefix", tableName: "Plinx", comment: "")

        struct HubEntry {
            let hub: Hub
            let library: Library?
        }

        let entries: [HubEntry] = viewModel.recentlyAdded.map { hub in
            HubEntry(hub: hub, library: matchedLibrary(for: hub, in: libraries, recentlyAddedPrefix: recentlyAddedPrefix))
        }

        // Use HomeLibraryGrouping helpers so none-agent libraries (e.g. YouTube)
        // with type=.movie are correctly excluded from the movies/TV row.
        let movieEntries = entries.filter { entry in
            guard let lib = entry.library else { return false }
            return HomeLibraryGrouping.isMoviesOrTV(lib) && lib.type == .movie
        }
        let showEntries = entries.filter { entry in
            guard let lib = entry.library else { return false }
            return HomeLibraryGrouping.isMoviesOrTV(lib) && lib.type == .show
        }
        let otherEntries = entries.filter { entry in
            HomeLibraryGrouping.isOtherVideo(entry.library)
        }

        let unmatchedEntries = entries.filter { $0.library == nil }
        if !unmatchedEntries.isEmpty {
            Self.logger.debug(
                "Unmatched recently-added hubs classified as otherVideos count=\(unmatchedEntries.count, privacy: .public) total=\(entries.count, privacy: .public)"
            )
        }

        Self.logger.debug(
            "Recently-added grouping total=\(entries.count, privacy: .public) movie=\(movieEntries.count, privacy: .public) show=\(showEntries.count, privacy: .public) other=\(otherEntries.count, privacy: .public)"
        )

        let visibleMovieEntries = movieEntries.filter { entry in
            guard let id = entry.library?.id else { return true }
            return !hiddenIds.contains(id)
        }
        let visibleShowEntries = showEntries.filter { entry in
            guard let id = entry.library?.id else { return true }
            return !hiddenIds.contains(id)
        }

        let movieVisible = !visibleMovieEntries.isEmpty
        let showVisible = !visibleShowEntries.isEmpty
        let movieEnabled = libraries.contains {
            $0.type == .movie && !HomeLibraryGrouping.isOtherVideo($0) && !hiddenIds.contains($0.id)
        }
        let showEnabled = libraries.contains {
            $0.type == .show && !HomeLibraryGrouping.isOtherVideo($0) && !hiddenIds.contains($0.id)
        }

        var groups: [HubGroup] = []

        if movieVisible || showVisible {
            if combineMoviesTV {
                // Combined: interleave movies and TV into a single row.
                var combined: [MediaDisplayItem] = []
                let m = StrimrAdapter.filteredItems(visibleMovieEntries.flatMap(\.hub.items), policy: safetyPolicy)
                let s = StrimrAdapter.filteredItems(visibleShowEntries.flatMap(\.hub.items), policy: safetyPolicy)
                let maxCount = max(m.count, s.count)
                for i in 0..<maxCount {
                    if i < m.count { combined.append(m[i]) }
                    if i < s.count { combined.append(s[i]) }
                }
                if !combined.isEmpty {
                    let title: String
                    if movieEnabled && showEnabled {
                        title = NSLocalizedString("home.recentlyAdded.tvAndMovies", tableName: "Plinx", comment: "")
                    } else if showVisible {
                        title = NSLocalizedString("home.recentlyAdded.tv", tableName: "Plinx", comment: "")
                    } else {
                        title = NSLocalizedString("home.recentlyAdded.movies", tableName: "Plinx", comment: "")
                    }
                    let combinedId = "combined.recentlyadded.movies+shows"
                    groups.append(HubGroup(
                        id: combinedId,
                        hub: Hub(id: combinedId, title: title, items: combined),
                        layout: .portrait
                    ))
                }
            } else {
                // Split: separate rows for movies and TV.
                let movieItems = StrimrAdapter.filteredItems(visibleMovieEntries.flatMap(\.hub.items), policy: safetyPolicy)
                if !movieItems.isEmpty {
                    let title = NSLocalizedString("home.recentlyAdded.movies", tableName: "Plinx", comment: "")
                    groups.append(HubGroup(
                        id: "recentlyadded.movies",
                        hub: Hub(id: "recentlyadded.movies", title: title, items: movieItems),
                        layout: .portrait
                    ))
                }
                let tvItems = StrimrAdapter.filteredItems(visibleShowEntries.flatMap(\.hub.items), policy: safetyPolicy)
                if !tvItems.isEmpty {
                    let title = NSLocalizedString("home.recentlyAdded.tv", tableName: "Plinx", comment: "")
                    groups.append(HubGroup(
                        id: "recentlyadded.tv",
                        hub: Hub(id: "recentlyadded.tv", title: title, items: tvItems),
                        layout: .portrait
                    ))
                }
            }
        }

        // Other-type hubs use letterbox (landscape) layout.
        for entry in otherEntries {
            let hub = entry.hub
            if let libId = entry.library?.id, hiddenIds.contains(libId) {
                continue
            }
            groups.append(HubGroup(id: hub.id, hub: hub, layout: .landscape))
        }

        if !entries.isEmpty && otherEntries.isEmpty && libraries.contains(where: { $0.type == .clip }) {
            Self.logger.debug("No other-video recently-added hubs matched from \(entries.count, privacy: .public) recently-added hubs")
        }

        guard !order.isEmpty else { return groups }
        return groups.sorted { a, b in
            orderIndexForGroup(a, order: order, libraries: libraries)
            < orderIndexForGroup(b, order: order, libraries: libraries)
        }
    }

    // MARK: - Recently added grouping

    /// Combined movie+TV recently-added groups (for "moviesAndTV" section).
    private var moviesTVGroups: [HubGroup] {
        displayedGroups.filter { $0.id == "combined.recentlyadded.movies+shows" }
    }

    /// Movies-only recently-added groups (for "recentMovies" section in split mode).
    private var recentMoviesGroups: [HubGroup] {
        displayedGroups.filter { $0.id == "recentlyadded.movies" }
    }

    /// TV-only recently-added groups (for "recentTV" section in split mode).
    private var recentTVGroups: [HubGroup] {
        displayedGroups.filter { $0.id == "recentlyadded.tv" }
    }

    /// Other-video recently-added groups (for "otherVideos" section).
    private var otherVideoGroups: [HubGroup] {
        let knownIds: Set<String> = ["combined.recentlyadded.movies+shows", "recentlyadded.movies", "recentlyadded.tv"]
        return displayedGroups.filter { !knownIds.contains($0.id) }
    }

    private func matchedLibrary(for hub: Hub, in libraries: [Library], recentlyAddedPrefix: String) -> Library? {
        HomeLibraryGrouping.matchLibrary(for: hub, in: libraries, recentlyAddedPrefix: recentlyAddedPrefix)
    }

    private func orderIndexForGroup(_ group: HubGroup, order: [String], libraries: [Library]) -> Int {
        if group.id == "combined.recentlyadded.movies+shows" {
            let indices = order.enumerated().compactMap { (i, libId) -> Int? in
                guard let lib = libraries.first(where: { $0.id == libId }),
                      lib.type == .movie || lib.type == .show else { return nil }
                return i
            }
            return indices.min() ?? Int.max
        }
        if group.id == "recentlyadded.movies" {
            let indices = order.enumerated().compactMap { (i, libId) -> Int? in
                guard let lib = libraries.first(where: { $0.id == libId }),
                      lib.type == .movie else { return nil }
                return i
            }
            return indices.min() ?? Int.max
        }
        if group.id == "recentlyadded.tv" {
            let indices = order.enumerated().compactMap { (i, libId) -> Int? in
                guard let lib = libraries.first(where: { $0.id == libId }),
                      lib.type == .show else { return nil }
                return i
            }
            return indices.min() ?? Int.max
        }
        let recentlyAddedPrefix = NSLocalizedString("home.recentlyAdded.prefix", tableName: "Plinx", comment: "")
        guard let libId = matchedLibrary(for: group.hub, in: libraries, recentlyAddedPrefix: recentlyAddedPrefix)?.id,
              let idx = order.firstIndex(of: libId) else { return Int.max }
        return idx
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
                mediaFocusModel.focusedMedia = playableItem
            }
            .onTapGesture { onSelectMedia(item) }
            .onLongPressGesture { onLongPressMedia(item) }
            .onMoveCommand { direction in
                handleMoveCommand(direction, fromRow: rowIndex, rowCount: rowCount)
            }
        #else
        Button {
            onSelectMedia(item)
        } label: {
            card
        }
        .buttonStyle(.plain)
        .onLongPressGesture { onLongPressMedia(item) }
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
        10
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
        20
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
            ZStack {
                if isFocused {
                    RoundedRectangle(cornerRadius: artworkCornerRadius + 4, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.78), lineWidth: 8)
                        .blur(radius: 10)
                        .padding(6)
                        .transition(.opacity)
                }

                ZStack(alignment: .bottom) {
                    MediaImageView(
                        viewModel: imageViewModel
                    )
                    .frame(width: cardWidth, height: thumbHeight)
                    .scaleEffect(isFocused ? 1.05 : 1.0)
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
                    .overlay {
                        RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous)
                            .stroke(isFocused ? Color.accentColor : .clear, lineWidth: isFocused ? 3.5 : 0)
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
                .shadow(color: isFocused ? Color.accentColor.opacity(0.62) : .clear, radius: isFocused ? 10 : 0)
                .shadow(color: isFocused ? Color.accentColor.opacity(0.24) : .clear, radius: isFocused ? 16 : 0)
            }
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
    let bottomBlendHeight: CGFloat

    static let `default` = TvBrowseHeroMetrics(
        heightRatio: 0.408,
        leadingSafeAreaReduction: 0,
        contentHorizontalPadding: 4,
        contentTopPadding: 1,
        metadataBottomPadding: 8,
        bottomBlendHeight: 46
    )

    static let home = TvBrowseHeroMetrics(
        heightRatio: 0.408,
        leadingSafeAreaReduction: 0.5,
        contentHorizontalPadding: 4,
        contentTopPadding: 0,
        metadataBottomPadding: 8,
        bottomBlendHeight: 46
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
                    heroSection(availableWidth: proxy.size.width)
                        .frame(height: heroHeight)
                        .background(Color.appBackground.ignoresSafeArea(edges: [.top, .horizontal]))
                        .overlay(alignment: .bottom) {
                            LinearGradient(
                                colors: [Color.clear, Color.appBackground],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: heroMetrics.bottomBlendHeight)
                        }

                    ScrollView {
                        rowsContent(scrollProxy)
                            .padding(.top, 10)
                            .padding(.bottom, 22)
                            .frame(minHeight: rowsHeight, alignment: .top)
                    }
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

                if showsFilters {
                    filterContent()
                }

                Spacer(minLength: 0)

                if let heroMedia {
                    VStack(alignment: .leading, spacing: 10) {
                        TvHeroMetadataPanel(media: heroMedia)
                            .frame(maxWidth: availableWidth * 0.72, alignment: .leading)
                    }
                    .padding(.bottom, heroMetrics.metadataBottomPadding)
                }
            }
            .padding(.horizontal, heroMetrics.contentHorizontalPadding)
            .padding(.top, heroMetrics.contentTopPadding)
        }
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
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.36))
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
            guard let value = rating.value else { continue }
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
                    .frame(
                        width: (proxy.size.width * 0.58) + 72,
                        height: proxy.size.height + 48
                    )
                    .clipped()
                    .mask(TvPinnedHeroImageMask())
                    .offset(x: 36, y: -24)
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

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .clear, location: 0.58),
                        .init(color: Color.appBackground.opacity(0.98), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
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
