import SwiftUI
import PlinxUI
import PlinxCore
import OSLog

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
        switch direction {
        case .up:
            if rowIndex == 0 {
                onRequestHomeNavigationFocus()
            } else {
                focusedCard = .card(row: rowIndex - 1, item: 0)
            }
        case .down:
            guard rowIndex + 1 < rowCount else { return }
            focusedCard = .card(row: rowIndex + 1, item: 0)
        default:
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
        12
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
                ZStack(alignment: .bottom) {
                    MediaImageView(
                        viewModel: imageViewModel
                    )
                    .frame(width: cardWidth, height: thumbHeight)
                    .scaleEffect(isFocused ? 1.06 : 1.0)
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
                            .stroke(isFocused ? Color.accentColor.opacity(0.9) : .clear, lineWidth: isFocused ? 2.5 : 0)
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
                .shadow(color: isFocused ? Color.accentColor.opacity(0.72) : .clear, radius: isFocused ? 22 : 0)
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
