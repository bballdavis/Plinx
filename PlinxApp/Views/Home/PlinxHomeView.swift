import SwiftUI
import PlinxUI

struct PlinxHomeView: View {
    @State var viewModel: SafeHomeViewModel
    var onSelectMedia: (MediaDisplayItem) -> Void

    @Environment(PlexAPIContext.self) private var plexApiContext

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
            Text("Loading your shows…")
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
                ForEach(viewModel.recentlyAdded) { hub in
                    if hub.hasItems {
                        hubRow(hub, landscape: false)
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 120) // clear of tab bar
        }
    }

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
