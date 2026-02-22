import SwiftUI
import PlinxUI
import PlinxCore

struct PlinxHomeView: View {
    @State var viewModel: SafeHomeViewModel
    var onSelectMedia: (MediaDisplayItem) -> Void

    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(LibraryStore.self) private var libraryStore

    // Plinx-specific home screen settings (separate from Library-tab visibility)
    @AppStorage("plinx.homeHiddenLibraryIds") private var homeHiddenIdsJson = "[]"
    @AppStorage("plinx.homeLibraryOrder") private var homeOrderJson = "[]"

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
                if let hub = viewModel.continueWatching, hub.hasItems {
                    hubRow(hub, layout: .landscape)
                }
                ForEach(displayedGroups) { group in
                    if group.hub.hasItems {
                        hubRow(group.hub, layout: group.layout)
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 40)
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

        // Separate movie / show hubs from other-type hubs.
        var movieHub: Hub?
        var showHub: Hub?
        var otherHubs: [Hub] = []

        for hub in viewModel.recentlyAdded {
            let id = hub.id.lowercased()
            if id.contains("movie") || id.contains("film") {
                movieHub = hub
            } else if id.contains("show") || id.contains("tv") || id.contains("series") {
                showHub = hub
            } else {
                otherHubs.append(hub)
            }
        }

        // Combine movie + show into one poster-style hub.
        let movieLibId = movieHub.flatMap { matchedLibraryId(for: $0, in: libraries) }
        let showLibId  = showHub.flatMap  { matchedLibraryId(for: $0, in: libraries) }
        let movieVisible = movieHub != nil && !hiddenIds.contains(movieLibId ?? "__none__")
        let showVisible  = showHub  != nil && !hiddenIds.contains(showLibId  ?? "__none__")

        var groups: [HubGroup] = []

        if movieVisible || showVisible {
            var combined: [MediaDisplayItem] = []
            let m = movieVisible ? (movieHub?.items ?? []) : []
            let s = showVisible  ? (showHub?.items  ?? []) : []
            let maxCount = max(m.count, s.count)
            for i in 0..<maxCount {
                if i < m.count { combined.append(m[i]) }
                if i < s.count { combined.append(s[i]) }
            }
            if !combined.isEmpty {
                let title = movieHub?.title ?? showHub?.title ?? "Recently Added"
                let combinedId = "combined.recentlyadded.movies+shows"
                groups.append(HubGroup(
                    id: combinedId,
                    hub: Hub(id: combinedId, title: title, items: combined),
                    layout: .portrait
                ))
            }
        }

        // Other-type hubs use letterbox (landscape) layout.
        for hub in otherHubs {
            let libId = matchedLibraryId(for: hub, in: libraries)
            if let libId, hiddenIds.contains(libId) { continue }
            groups.append(HubGroup(id: hub.id, hub: hub, layout: .landscape))
        }

        guard !order.isEmpty else { return groups }
        return groups.sorted { a, b in
            orderIndexForGroup(a, order: order, libraries: libraries)
            < orderIndexForGroup(b, order: order, libraries: libraries)
        }
    }

    private func matchedLibraryId(for hub: Hub, in libraries: [Library]) -> String? {
        let id = hub.id.lowercased()
        return libraries.first { lib in
            switch lib.type {
            case .movie: return id.contains("movie") || id.contains("film")
            case .show:  return id.contains("show") || id.contains("tv") || id.contains("series")
            default:     return id.contains(lib.id.lowercased()) || id.contains(lib.title.lowercased())
            }
        }?.id
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
        guard let libId = matchedLibraryId(for: group.hub, in: libraries),
              let idx = order.firstIndex(of: libId) else { return Int.max }
        return idx
    }

    // MARK: - Hub row

    private func hubRow(_ hub: Hub, layout: CardLayout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hub.title)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(hub.items) { item in
                        mediaCard(item, layout: layout)
                            .onTapGesture { onSelectMedia(item) }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func mediaCard(_ item: MediaDisplayItem, layout: CardLayout) -> some View {
        let isLandscape = layout == .landscape
        let cardWidth: CGFloat = isLandscape ? 200 : 110
        let ratio: CGFloat = isLandscape ? 16.0 / 9.0 : 2.0 / 3.0

        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                MediaImageView(
                    viewModel: MediaImageViewModel(
                        context: plexApiContext,
                        artworkKind: .thumb,
                        media: item
                    )
                )
                .frame(width: cardWidth, height: cardWidth / ratio)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

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
    }
}

// MARK: - JSON helpers (file-private)

private func decodeStringArray(_ json: String) -> [String] {
    guard let data = json.data(using: .utf8),
          let arr = try? JSONDecoder().decode([String].self, from: data)
    else { return [] }
    return arr
}
