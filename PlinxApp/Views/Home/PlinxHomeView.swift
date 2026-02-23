import SwiftUI
import PlinxUI
import PlinxCore
import OSLog

struct PlinxHomeView: View {
    private static let logger = Logger(subsystem: "com.plinx.app", category: "home")

    @State var viewModel: SafeHomeViewModel
    var onSelectMedia: (MediaDisplayItem) -> Void

    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(LibraryStore.self) private var libraryStore

    // Plinx-specific home screen settings (separate from Library-tab visibility)
    @AppStorage("plinx.homeHiddenLibraryIds") private var homeHiddenIdsJson = "[]"
    @AppStorage("plinx.homeLibraryOrder") private var homeOrderJson = "[]"
    @AppStorage("plinx.homeSectionOrder") private var homeSectionOrderJson = "[]"

    /// Section IDs in user-configured display order.
    private var orderedHomeSections: [String] {
        let stored = decodeStringArray(homeSectionOrderJson)
        let defaults = ["continueWatching", "moviesAndTV", "otherVideos"]
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
        .refreshable { await viewModel.reload() }
    }

    // MARK: - Subviews

    private var fullscreenLoading: some View {
        VStack(spacing: 20) {
            PlinxieLoadingView()
            Text("home.loading", tableName: "Plinx")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(orderedHomeSections, id: \.self) { sectionId in
                    homeSectionView(sectionId)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    @ViewBuilder
    private func homeSectionView(_ sectionId: String) -> some View {
        switch sectionId {
        case "continueWatching":
            if let hub = viewModel.continueWatching, hub.hasItems {
                hubRow(hub, layout: .landscape, sectionKey: "continueWatching")
            }
        case "moviesAndTV":
            ForEach(moviesTVGroups) { group in
                if group.hub.hasItems {
                    hubRow(group.hub, layout: group.layout, sectionKey: "moviesAndTV")
                }
            }
        case "otherVideos":
            ForEach(otherVideoGroups) { group in
                if group.hub.hasItems {
                    hubRow(group.hub, layout: group.layout, sectionKey: "otherVideos")
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Hub layout groups

    enum CardLayout { case portrait, landscape }

    private struct HubGroup: Identifiable {
        let id: String
        let hub: Hub
        let layout: CardLayout
    }

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

        let movieEntries = entries.filter { $0.library?.type == .movie }
        let showEntries = entries.filter { $0.library?.type == .show }
        let otherEntries = entries.filter { entry in
            guard let type = entry.library?.type else { return true }
            return type != .movie && type != .show
        }

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

        var groups: [HubGroup] = []

        if movieVisible || showVisible {
            var combined: [MediaDisplayItem] = []
            let m = visibleMovieEntries.flatMap(\.hub.items)
            let s = visibleShowEntries.flatMap(\.hub.items)
            let maxCount = max(m.count, s.count)
            for i in 0..<maxCount {
                if i < m.count { combined.append(m[i]) }
                if i < s.count { combined.append(s[i]) }
            }
            if !combined.isEmpty {
                let title: String
                if movieVisible && showVisible {
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
        }

        // Other-type hubs use letterbox (landscape) layout.
        for entry in otherEntries {
            let hub = entry.hub
            let libId = entry.library?.id
            if let libId, hiddenIds.contains(libId) { continue }
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

    /// Combined movie+TV recently-added groups (for "moviesAndTV" section).
    private var moviesTVGroups: [HubGroup] {
        displayedGroups.filter { $0.id == "combined.recentlyadded.movies+shows" }
    }

    /// Other-video recently-added groups (for "otherVideos" section).
    private var otherVideoGroups: [HubGroup] {
        displayedGroups.filter { $0.id != "combined.recentlyadded.movies+shows" }
    }

    private func matchedLibrary(for hub: Hub, in libraries: [Library], recentlyAddedPrefix: String) -> Library? {
        let title = hub.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            let stripped = title
                .replacingOccurrences(of: recentlyAddedPrefix, with: "", options: [.caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let exact = libraries.first(where: { $0.title.compare(stripped, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                return exact
            }
            if let contains = libraries.first(where: { stripped.localizedCaseInsensitiveContains($0.title) || $0.title.localizedCaseInsensitiveContains(stripped) }) {
                return contains
            }
        }

        let id = hub.id.lowercased()
        return libraries.first { lib in
            switch lib.type {
            case .movie: return id.contains("movie") || id.contains("film")
            case .show:  return id.contains("show") || id.contains("tv") || id.contains("series")
            default:     return id.contains(lib.id.lowercased()) || id.contains(lib.title.lowercased())
            }
        }
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
        let recentlyAddedPrefix = NSLocalizedString("home.recentlyAdded.prefix", tableName: "Plinx", comment: "")
        guard let libId = matchedLibrary(for: group.hub, in: libraries, recentlyAddedPrefix: recentlyAddedPrefix)?.id,
              let idx = order.firstIndex(of: libId) else { return Int.max }
        return idx
    }

    // MARK: - Hub row

    private func hubRow(_ hub: Hub, layout: CardLayout, sectionKey: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hub.title)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .accessibilityIdentifier("home.section.\(sectionKey)")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(hub.items.enumerated()), id: \.element.id) { index, item in
                        mediaCard(item, layout: layout, sectionKey: sectionKey, index: index)
                            .onTapGesture { onSelectMedia(item) }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .accessibilityIdentifier("home.hub.\(sectionKey)")
    }

    private func mediaCard(_ item: MediaDisplayItem, layout: CardLayout, sectionKey: String, index: Int) -> some View {
        let isLandscape = layout == .landscape
        let prefersThumbForLandscape = isLandscape && item.type == .clip
        let cardWidth: CGFloat = isLandscape ? 200 : 110
        let ratio: CGFloat = isLandscape ? 16.0 / 9.0 : 2.0 / 3.0

        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                MediaImageView(
                    viewModel: MediaImageViewModel(
                        context: plexApiContext,
                        artworkKind: prefersThumbForLandscape ? .thumb : (isLandscape ? .art : .thumb),
                        media: item
                    )
                )
                .frame(width: cardWidth, height: cardWidth / ratio)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityIdentifier("home.thumbnail.\(sectionKey).\(index)")

                if let pct = item.viewProgressPercentage, pct > 0 {
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(min(pct / 100, 1)), height: 3)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 4)
                    }
                    .frame(width: cardWidth, height: cardWidth / ratio)
                }
            }

            Text(item.primaryLabel)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: cardWidth, alignment: .leading)

            if let sub = item.secondaryLabel {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .frame(width: cardWidth, alignment: .leading)
            }
        }
        .frame(width: cardWidth)
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
