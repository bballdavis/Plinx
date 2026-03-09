import SwiftUI
import Foundation

#if canImport(UIKit)
import UIKit
private typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias PlatformImage = NSImage
#endif

/// The main downloads tab: a 5-column poster grid with an Edit button that
/// opens the download management list (storage info, delete, etc.).
@MainActor
struct PlinxDownloadsGridView: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(PlexAPIContext.self) private var context
    @EnvironmentObject private var mainCoordinator: MainCoordinator
    @State private var selectedDownload: DownloadItem?
    @State private var showManage = false
    @State private var layoutMode: LayoutMode = .grid
    @State private var viewportSize: CGSize = .zero

    private enum LayoutMode {
        case grid
        case list

        var iconName: String {
            switch self {
            case .grid:
                return "list.bullet"
            case .list:
                return "square.grid.2x2"
            }
        }
    }

    private let gridSpacing: CGFloat = 10

    private struct GridPosterLayout {
        let posterSize: CGSize
        let posterWidth: CGFloat
        let posterHeight: CGFloat
        let cardWidth: CGFloat
    }

    private var gridPosterHeight: CGFloat {
        isPortraitViewport ? 235 : 220
    }

    private let gridTextHeight: CGFloat = 74
    private let gridRowSpacing: CGFloat = 18

    private var gridMinCardWidth: CGFloat {
        isPortraitViewport ? 132 : 148
    }

    private var gridMaxCardWidth: CGFloat {
        isPortraitViewport ? 220 : 300
    }

    private var gridCardHeight: CGFloat {
        gridPosterHeight + gridTextHeight + 8
    }

    private var isPortraitViewport: Bool {
        let resolvedSize = viewportSize == .zero ? UIScreen.main.bounds.size : viewportSize
        return resolvedSize.height >= resolvedSize.width
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if downloadManager.isOffline {
                    Label {
                        Text("downloads.offline.banner", tableName: "Plinx")
                    } icon: {
                        Image(systemName: "wifi.slash")
                    }
                        .foregroundStyle(.orange)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }

                if downloadManager.sortedItems.isEmpty {
                    emptyState
                } else {
                    if layoutMode == .grid {
                        DownloadsAdaptiveFlowLayout(itemSpacing: gridSpacing, rowSpacing: gridRowSpacing) {
                            ForEach(downloadManager.sortedItems) { item in
                                gridCell(item)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 120)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(downloadManager.sortedItems) { item in
                                listRow(item)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 120)
                    }
                }
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: DownloadsViewportSizePreferenceKey.self, value: proxy.size)
            }
        }
        .onPreferenceChange(DownloadsViewportSizePreferenceKey.self) { newSize in
            guard newSize != .zero else { return }
            viewportSize = newSize
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            titleRow
        }
        .navigationDestination(isPresented: $showManage) {
            PlinxDownloadsManageView()
        }
        .fullScreenCover(item: $selectedDownload) { item in
            if let localURL = downloadManager.localVideoURL(for: item) {
                PlayerWrapper(
                    viewModel: PlayerViewModel(
                        localMedia: downloadManager.localMediaItem(for: item),
                        localPlaybackURL: localURL,
                        context: context,
                    ),
                )
            }
        }
        .task(id: artworkReconciliationID) {
            await downloadManager.reconcileArtworkMetadataIfNeeded(context: context)
        }
    }

    private var artworkReconciliationID: String {
        downloadManager.sortedItems
            .map { item in
                "\(item.id):\(item.metadata.artworkLayoutStyle?.rawValue ?? "unknown")"
            }
            .joined(separator: "|")
    }

    // MARK: - Header

    private var titleRow: some View {
        ZStack {
            Text("tabs.downloads", tableName: "Plinx")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white.opacity(0.95))

            HStack {
                chromeButton(systemImage: "chevron.left") {
                    mainCoordinator.tab = .home
                }

                Spacer()
                HStack(spacing: 12) {
                    chromeButton(systemImage: layoutMode.iconName) {
                        layoutMode = layoutMode == .grid ? .list : .grid
                    }

                    chromeButton(systemImage: "pencil") {
                    showManage = true
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - Grid cells

    private func gridCell(_ item: DownloadItem) -> some View {
        let localPoster = localPosterImage(for: item)
        let layout = gridPosterLayout(for: item, poster: localPoster)

        return VStack(alignment: .leading, spacing: 6) {
            posterCell(
                item,
                poster: localPoster,
                posterSize: layout.posterSize,
                posterWidth: layout.posterWidth,
                posterHeight: layout.posterHeight,
                cardWidth: layout.cardWidth
            )
            metadataLabels(for: item, titleLineLimit: 2)
                .frame(width: layout.cardWidth, height: gridTextHeight, alignment: .topLeading)
        }
        .frame(width: layout.cardWidth, height: gridCardHeight, alignment: .topLeading)
    }

    private func posterCell(
        _ item: DownloadItem,
        poster: PlatformImage?,
        posterSize: CGSize,
        posterWidth: CGFloat,
        posterHeight: CGFloat,
        cardWidth: CGFloat
    ) -> some View {
        return Button {
            guard item.isPlayable else { return }
            selectedDownload = item
        } label: {
            Color.clear
                .frame(width: cardWidth, height: posterHeight)
                .overlay {
                    posterArtwork(
                        for: item,
                        poster: poster,
                        posterSize: posterSize
                    )
                    .frame(width: posterWidth, height: posterHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
        }
        .buttonStyle(.plain)
        .opacity(item.isPlayable ? 1 : 0.85)
    }

    private func listRow(_ item: DownloadItem) -> some View {
        let isPortrait = item.metadata.prefersPortraitArtwork
        let posterSize = isPortrait ? CGSize(width: 45, height: 68) : CGSize(width: 78, height: 44)

        return Button {
            guard item.isPlayable else { return }
            selectedDownload = item
        } label: {
            HStack(alignment: .center, spacing: 12) {
                posterImage(for: item)
                    .frame(width: posterSize.width, height: posterSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    metadataLabels(for: item, titleLineLimit: 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if item.isPlayable {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(.plain)
        .opacity(item.isPlayable ? 1 : 0.85)
    }

    private func metadataLabels(for item: DownloadItem, titleLineLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.metadata.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(titleLineLimit)

            if secondaryLeadingLabel(for: item) != nil || secondaryTrailingLabel(for: item) != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let secondary = secondaryLeadingLabel(for: item) {
                        Text(secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if let trailing = secondaryTrailingLabel(for: item) {
                        Text(trailing)
                            .lineLimit(1)
                    }
                }
                .font(.headline)
                .foregroundStyle(.secondary)
            }

            if let tertiary = tertiaryLabel(for: item) {
                Text(tertiary)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func secondaryLeadingLabel(for item: DownloadItem) -> String? {
        switch item.metadata.type {
        case .episode:
            return item.metadata.subtitle
        case .movie:
            return joinedMeta([item.metadata.year.map(String.init), item.metadata.contentRating])
        case .season:
            return item.metadata.parentTitle
        case .show:
            return joinedMeta([item.metadata.contentRating, item.metadata.year.map(String.init)])
        case .clip:
            return item.metadata.year.map(String.init)
        default:
            return item.metadata.subtitle
        }
    }

    private func secondaryTrailingLabel(for item: DownloadItem) -> String? {
        guard item.metadata.type == .clip, let duration = item.metadata.duration else {
            return nil
        }

        return duration.mediaDurationText()
    }

    private func tertiaryLabel(for item: DownloadItem) -> String? {
        switch item.status {
        case .queued:
            return NSLocalizedString("downloads.status.queued", tableName: "Plinx", comment: "")
        case .downloading:
            return String.localizedStringWithFormat(
                NSLocalizedString("downloads.status.downloading %lld", tableName: "Plinx", comment: ""),
                Int64((item.progress * 100).rounded())
            )
        case .completed:
            return nil
        case .failed:
            return NSLocalizedString("downloads.status.failed", tableName: "Plinx", comment: "")
        }
    }

    private func joinedMeta(_ parts: [String?]) -> String? {
        let values = parts.compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        guard !values.isEmpty else { return nil }
        return values.joined(separator: " • ")
    }

    private func formattedBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func chromeButton(systemImage: String, action: @escaping () -> Void) -> some View {
        PlinxChromeButton(systemImage: systemImage, action: action)
    }

    private func posterArtwork(
        for item: DownloadItem,
        poster: PlatformImage?,
        posterSize: CGSize
    ) -> some View {
        return ZStack(alignment: .bottom) {
            posterImageView(poster)
                .accessibilityIdentifier("downloads.thumbnail.\(item.id)")

            if item.status == .downloading {
                VStack {
                    Spacer()
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                        .accessibilityIdentifier("downloads.progress.\(item.id)")
                }
            }
        }
        .frame(width: posterSize.width, height: posterSize.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            if item.status == .downloading || item.status == .queued {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
    }

    private func gridPosterLayout(for item: DownloadItem, poster: PlatformImage?) -> GridPosterLayout {
        let posterSize = posterFrameSize(for: item)
        let posterWidth = posterSize.width
        let cardWidth = gridCardWidth(for: posterWidth)
        return GridPosterLayout(
            posterSize: posterSize,
            posterWidth: posterWidth,
            posterHeight: posterSize.height,
            cardWidth: cardWidth
        )
    }

    private func posterFrameSize(for item: DownloadItem) -> CGSize {
        if item.metadata.prefersPortraitArtwork {
            let width = min(gridPosterHeight * DownloadsArtworkLayoutPolicy.portraitAspectRatio, gridMaxCardWidth)
            return CGSize(width: width, height: gridPosterHeight)
        }

        let rotatedHeight = min(gridPosterHeight * DownloadsArtworkLayoutPolicy.portraitAspectRatio, 160)
        let rotatedWidth = min(gridPosterHeight, gridMaxCardWidth)
        return CGSize(width: rotatedWidth, height: rotatedHeight)
    }

    private func gridCardWidth(for posterWidth: CGFloat) -> CGFloat {
        max(posterWidth, gridMinCardWidth)
    }

    private func localPosterImage(for item: DownloadItem) -> PlatformImage? {
        guard let posterURL = downloadManager.localPosterURL(for: item) else { return nil }
        return PlatformImage(contentsOfFile: posterURL.path)
    }

    @ViewBuilder
    private func posterImage(for item: DownloadItem) -> some View {
        if let uiImage = localPosterImage(for: item) {
            posterImageView(uiImage)
        } else {
            posterImageView(nil)
        }
    }

    @ViewBuilder
    private func posterImageView(_ image: PlatformImage?) -> some View {
        if let image {
#if canImport(UIKit)
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
#elseif canImport(AppKit)
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
#endif
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.gray.opacity(0.2))
                .overlay {
                    Image(systemName: "film")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("downloads.empty.title", tableName: "Plinx")
                .font(.headline)
            Text("downloads.empty.message", tableName: "Plinx")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 32)
    }
}

// MARK: - Manage view wrapper

/// Wraps the original DownloadsView (list + storage info) with a custom
/// back button matching the app's navigation chrome style.
@MainActor
struct PlinxDownloadsManageView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DownloadsView()
            .safeAreaInset(edge: .top, spacing: 0) {
                manageHeader
            }
            .toolbar(.hidden, for: .navigationBar)
    }

    private var manageHeader: some View {
        HStack(spacing: 12) {
            PlinxChromeButton(systemImage: "chevron.left") {
                dismiss()
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

private struct DownloadsViewportSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct DownloadsAdaptiveFlowLayout: Layout {
    let itemSpacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let frames = arrangedFrames(for: subviews, in: proposal.width)
        guard let lastFrame = frames.last else {
            return CGSize(width: proposal.width ?? 0, height: 0)
        }

        let contentWidth = frames.map(\.maxX).max() ?? 0
        return CGSize(
            width: proposal.width ?? contentWidth,
            height: lastFrame.maxY
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let frames = arrangedFrames(for: subviews, in: bounds.width)

        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func arrangedFrames(for subviews: Subviews, in availableWidth: CGFloat?) -> [CGRect] {
        let maxWidth = max(availableWidth ?? UIScreen.main.bounds.width, 1)
        var frames: [CGRect] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let width = min(size.width, maxWidth)
            let height = size.height

            if currentX > 0, currentX + width > maxWidth {
                currentX = 0
                currentY += rowHeight + rowSpacing
                rowHeight = 0
            }

            frames.append(CGRect(x: currentX, y: currentY, width: width, height: height))
            currentX += width + itemSpacing
            rowHeight = max(rowHeight, height)
        }

        return frames
    }
}
