import PlinxCore
import PlinxUI
import SwiftUI

struct PlinxLibraryPortraitMediaCard: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    let media: MediaDisplayItem
    let height: CGFloat?
    let width: CGFloat?
    let showsLabels: Bool
    let onTap: () -> Void

    private let aspectRatio: CGFloat = 2 / 3

    init(
        media: MediaDisplayItem,
        height: CGFloat? = nil,
        width: CGFloat? = nil,
        showsLabels: Bool,
        onTap: @escaping () -> Void
    ) {
        self.media = media
        self.height = height
        self.width = width
        self.showsLabels = showsLabels
        self.onTap = onTap
    }

    private var defaultHeight: CGFloat {
        #if os(tvOS)
        320
        #elseif os(macOS)
        260
        #else
        sizeClass == .compact ? 180 : 240
        #endif
    }

    var body: some View {
        let resolvedHeight = height ?? (width.map { $0 / aspectRatio } ?? defaultHeight)
        let resolvedWidth = width ?? (height.map { $0 * aspectRatio } ?? resolvedHeight * aspectRatio)
        PlinxLibraryMediaCard(
            size: CGSize(width: resolvedWidth, height: resolvedHeight),
            media: media,
            artworkKind: .thumb,
            showsLabels: showsLabels,
            onTap: onTap
        )
    }
}

/// Plinx's library-detail landscape card honors the library-specific artwork
/// preference so Other Videos displays each item's Plex thumbnail.
struct PlinxLibraryLandscapeMediaCard: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.preferredLandscapeArtworkKind) private var preferredArtworkKind

    let media: MediaDisplayItem
    let height: CGFloat?
    let width: CGFloat?
    let showsLabels: Bool
    let onTap: () -> Void

    private let aspectRatio: CGFloat = 16 / 9

    init(
        media: MediaDisplayItem,
        height: CGFloat? = nil,
        width: CGFloat? = nil,
        showsLabels: Bool,
        onTap: @escaping () -> Void
    ) {
        self.media = media
        self.height = height
        self.width = width
        self.showsLabels = showsLabels
        self.onTap = onTap
    }

    private var defaultHeight: CGFloat {
        #if os(tvOS)
        180
        #elseif os(macOS)
        140
        #else
        sizeClass == .compact ? 90 : 124
        #endif
    }

    var body: some View {
        let resolvedHeight = height ?? (width.map { $0 / aspectRatio } ?? defaultHeight)
        let resolvedWidth = width ?? (height.map { $0 * aspectRatio } ?? resolvedHeight * aspectRatio)
        PlinxLibraryMediaCard(
            size: CGSize(width: resolvedWidth, height: resolvedHeight),
            media: media,
            artworkKind: ArtworkSelectionPolicy.landscapeCardArtworkKind(
                preferredArtworkKind: preferredArtworkKind
            ),
            showsLabels: showsLabels,
            onTap: onTap
        )
    }
}

/// One Plinx-owned media-card renderer for every library surface. Keeping the
/// focus decoration here prevents individual tabs from drifting back to the
/// inset-ring behavior of the upstream card.
private struct PlinxLibraryMediaCard: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    #if os(tvOS)
    @Environment(MediaFocusModel.self) private var focusModel
    @FocusState private var isFocused: Bool
    #endif

    let size: CGSize
    let media: MediaDisplayItem
    let artworkKind: MediaImageViewModel.ArtworkKind
    let showsLabels: Bool
    let onTap: () -> Void

    private let cornerRadius: CGFloat = 14

    private var progress: Double? {
        media.viewProgressPercentage.map { min(max($0 / 100, 0), 1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: labelSpacing) {
            artwork

            if showsLabels {
                VStack(alignment: .leading, spacing: 4) {
                    Text(media.primaryLabel)
                        .font(primaryLabelFont)
                        .lineLimit(1)

                    if let secondaryLabel = media.secondaryLabel, !secondaryLabel.isEmpty {
                        Text(secondaryLabel)
                            .font(secondaryLabelFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let tertiaryLabel = media.tertiaryLabel, !tertiaryLabel.isEmpty {
                        Text(tertiaryLabel)
                            .font(secondaryLabelFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(width: size.width, alignment: .leading)
        #if os(tvOS)
        .focusable()
        .focused($isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused, let playableItem = media.playableItem {
                focusModel.focusedMedia = playableItem
            }
        }
        .onPlayPauseCommand(perform: onTap)
        #endif
        .onTapGesture(perform: onTap)
    }

    private var artwork: some View {
        MediaImageView(
            viewModel: MediaImageViewModel(
                context: plexApiContext,
                artworkKind: artworkKind,
                media: media
            )
        )
        .frame(width: size.width, height: size.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            WatchStatusBadge(media: media)
        }
        .overlay(alignment: .bottomLeading) {
            if let progress, progress > 0 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        }
        #if os(tvOS)
        .plinxTVCardFocusArtwork(isFocused: isFocused, cornerRadius: cornerRadius)
        #endif
    }

    private var labelSpacing: CGFloat {
        #if os(tvOS)
        12
        #else
        8
        #endif
    }

    private var primaryLabelFont: Font {
        #if os(tvOS)
        size.width < 180 ? .footnote : .subheadline
        #else
        .subheadline
        #endif
    }

    private var secondaryLabelFont: Font {
        #if os(tvOS)
        size.width < 180 ? .caption2 : .footnote
        #else
        .footnote
        #endif
    }
}
