import SwiftUI
import PlinxUI

struct PlinxMediaDetailView: View {
    @State var viewModel: SafeMediaDetailViewModel
    var onPlay: (String, PlexItemType) -> Void
    var onSelectRelated: (MediaDisplayItem) -> Void

    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(\.plinxTheme) private var theme

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isBlocked {
                blockedView
            } else {
                content
            }
        }
        .task { await viewModel.loadDetails() }
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Blocked

    private var blockedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(.orange)
            Text("media.unavailable.title", tableName: "Plinx")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("media.unavailable.description", tableName: "Plinx")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main content

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                heroSection
                    .frame(height: 260)

                detailSection
                    .padding(.top, 20)
                    .padding(.horizontal, 20)

                if viewModel.media.type == .show {
                    seasonsSection
                }

                if !viewModel.relatedHubs.isEmpty {
                    relatedSection
                        .padding(.top, 24)
                }
            }
            .padding(.bottom, 120)
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            // Backdrop
            if let url = viewModel.heroImageURL {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        Color.gray.opacity(0.25)
                    }
                }
                .clipped()
            } else {
                Color.gray.opacity(0.15)
            }

            // Gradient
            LinearGradient(
                colors: viewModel.backdropGradient.isEmpty
                    ? [.clear, .black]
                    : viewModel.backdropGradient.map { $0 } + [.black.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Detail

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title + year
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.media.primaryLabel)
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    if let year = viewModel.media.year {
                        Text(String(year))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let rating = viewModel.media.contentRating {
                        ratingBadge(rating)
                    }
                    if let runtime = viewModel.media.duration {
                        Text(runtime.formatted())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Play button
            LiquidGlassButton(LocalizedStringResource("media.detail.play", table: "Plinx")) {
                Task {
                    if let key = await viewModel.playbackRatingKey() {
                        onPlay(key, viewModel.media.plexType)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Summary
            if let summary = viewModel.media.summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
    }

    private func ratingBadge(_ rating: String) -> some View {
        Text(rating)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.orange.opacity(0.85)))
    }

    // MARK: - Seasons

    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("media.detail.seasons", tableName: "Plinx")
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 20)

            if viewModel.isLoadingSeasons {
                ProgressView().padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(viewModel.seasons) { season in
                            seasonPill(season)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .padding(.top, 20)
        .task {
            await viewModel.loadSeasonsIfNeeded()
        }
    }

    private func seasonPill(_ season: MediaItem) -> some View {
        let isSelected = viewModel.selectedSeasonId == season.id
        return Button {
            Task { await viewModel.selectSeason(id: season.id) }
        } label: {
            Text(season.title)
                .font(.subheadline.bold())
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isSelected ? Color.orange : Color.white.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Related

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("media.detail.related", tableName: "Plinx")
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 20)

            ForEach(viewModel.relatedHubs) { hub in
                if hub.hasItems {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(hub.items) { item in
                                Button { onSelectRelated(item) } label: {
                                    relatedCard(item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
    }

    private func relatedCard(_ item: MediaDisplayItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MediaImageView(
                viewModel: MediaImageViewModel(
                    context: plexApiContext,
                    artworkKind: .thumb,
                    media: item
                )
            )
            .frame(width: 100, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(item.primaryLabel)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
        }
    }
}
