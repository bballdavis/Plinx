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
            Text("home.loading")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if let hub = viewModel.continueWatching, hub.hasItems {
                    hubRow(hub, landscape: true)
                }
                ForEach(displayedHubs) { hub in
                    if hub.hasItems {
                        hubRow(hub, landscape: false)
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Home library filtering & ordering

    private var displayedHubs: [Hub] {
        let hiddenIds = decodeStringArray(homeHiddenIdsJson)
        let order = decodeStringArray(homeOrderJson)

        let filtered = viewModel.recentlyAdded.filter { hub in
            guard !hiddenIds.isEmpty else { return true }
            if let matchingLibrary = library(for: hub, in: libraryStore.libraries) {
                return !hiddenIds.contains(matchingLibrary.id)
            }
            return true
        }

        guard !order.isEmpty else { return filtered }
        return filtered.sorted { a, b in
            let ai = orderIndex(for: a, order: order, libraries: libraryStore.libraries)
            let bi = orderIndex(for: b, order: order, libraries: libraryStore.libraries)
            return ai < bi
        }
    }

    private func orderIndex(for hub: Hub, order: [String], libraries: [Library]) -> Int {
        guard let lib = library(for: hub, in: libraries),
              let idx = order.firstIndex(of: lib.id) else {
            return Int.max
        }
        return idx
    }

    private func library(for hub: Hub, in libraries: [Library]) -> Library? {
        let id = hub.id.lowercased()
        return libraries.first { lib in
            switch lib.type {
            case .movie: return id.contains("movie") || id.contains("film")
            case .show:  return id.contains("show") || id.contains("tv") || id.contains("series")
            default:     return false
            }
        }
    }

    // MARK: - Hub row

    private func hubRow(_ hub: Hub, landscape: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hub.title)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(hub.items) { item in
                        mediaCard(item, landscape: landscape)
                            .onTapGesture { onSelectMedia(item) }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func mediaCard(_ item: MediaDisplayItem, landscape: Bool) -> some View {
        let cardWidth: CGFloat = landscape ? 200 : 110
        let ratio: CGFloat = landscape ? 16 / 9 : 2 / 3

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
                            .fill(Color.orange)
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
