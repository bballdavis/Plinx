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
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ParentalAccessCoordinator.self) private var parentalAccessCoordinator
    @Environment(DownloadOwnershipStore.self) private var downloadOwnershipStore
    @Environment(\.safetyPolicy) private var safetyPolicy
    @EnvironmentObject private var mainCoordinator: MainCoordinator
    @State private var selectedDownload: DownloadItem?
    @State private var showManage = false
    @State private var layoutMode: LayoutMode = .grid
    @State private var viewportSize: CGSize = .zero

    private var accessPolicy: DownloadAccessPolicy {
        DownloadAccessPolicy(
            safetyPolicy: safetyPolicy,
            currentIdentity: sessionManager.plinxDownloadOwnerIdentity,
            ownershipStore: downloadOwnershipStore
        )
    }

    private var visibleDownloads: [DownloadItem] {
        accessPolicy.filter(downloadManager.sortedItems)
    }

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

    private var gridSpacing: CGFloat {
        #if os(tvOS)
        18
        #else
        12
        #endif
    }

    private var gridHorizontalPadding: CGFloat {
        #if os(tvOS)
        42
        #else
        16
        #endif
    }

    private var gridTextHeight: CGFloat {
        #if os(tvOS)
        96
        #else
        78
        #endif
    }

    private var gridRowSpacing: CGFloat {
        #if os(tvOS)
        26
        #else
        18
        #endif
    }

    private var listArtworkSlotSize: CGSize {
        CGSize(width: 78, height: 68)
    }

    /// Column sizing for the downloads grid. Portrait viewports favor more,
    /// narrower columns; landscape viewports allow slightly wider posters.
    private var gridMetrics: DownloadsGridLayoutPolicy.Metrics {
        #if os(tvOS)
        DownloadsGridLayoutPolicy.Metrics(
            minimumColumnWidth: isPortraitViewport ? 190 : 210,
            maximumColumnWidth: 300,
            columnSpacing: gridSpacing
        )
        #else
        DownloadsGridLayoutPolicy.Metrics(
            minimumColumnWidth: isPortraitViewport ? 136 : 150,
            maximumColumnWidth: 220,
            columnSpacing: gridSpacing
        )
        #endif
    }

    private var resolvedViewportSize: CGSize {
        viewportSize == .zero ? UIScreen.main.bounds.size : viewportSize
    }

    private var gridAvailableWidth: CGFloat {
        max(resolvedViewportSize.width - gridHorizontalPadding * 2, 1)
    }

    private var isPortraitViewport: Bool {
        resolvedViewportSize.height >= resolvedViewportSize.width
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if visibleDownloads.isEmpty {
                    emptyState
                } else {
                    if layoutMode == .grid {
                        downloadsGrid
                            .padding(.horizontal, gridHorizontalPadding)
                            .padding(.top, 8)
                            .padding(.bottom, 120)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(visibleDownloads) { item in
                                listRow(item)
                            }
                        }
                        .padding(.horizontal, gridHorizontalPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 120)
                    }
                }
            }
        }
        .accessibilityIdentifier("downloads.grid.scroll")
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
        .sheet(isPresented: $showManage) {
            Group {
                if parentalAccessCoordinator.isUnlocked {
                    PlinxDownloadsManageView()
                } else {
                    ParentalGateView(onAllowed: {})
                }
            }
        }
        .onChange(of: showManage) { _, isPresented in
            if !isPresented {
                parentalAccessCoordinator.lock()
            }
        }
        .fullScreenCover(item: $selectedDownload) { item in
            OfflineDownloadPlayerView(item: item)
        }
        .task(id: artworkReconciliationID) {
            downloadOwnershipStore.prune(keeping: Set(downloadManager.items.map(\.id)))
            downloadManager.resumePendingDownloads(
                context: context,
                eligibleDownloadIDs: Set(visibleDownloads.map(\.id))
            )
            await downloadManager.reconcileArtworkMetadataIfNeeded(context: context)
        }
    }

    private var artworkReconciliationID: String {
        return visibleDownloads
            .map { item in
                "\(item.id):\(item.metadata.artworkLayoutStyle?.rawValue ?? "unknown")"
            }
            .joined(separator: "|")
    }

    // MARK: - Header

    private var titleRow: some View {
        PlinxPageHeader(
            title: Text("tabs.downloads", tableName: "Plinx"),
            onBack: { mainCoordinator.tab = .home }
        ) {
            HStack(spacing: 12) {
                chromeButton(systemImage: layoutMode.iconName) {
                    layoutMode = layoutMode == .grid ? .list : .grid
                }

                chromeButton(systemImage: "pencil") {
                    parentalAccessCoordinator.lock()
                    showManage = true
                }
            }
        }
    }

    // MARK: - Grid

    /// Equal-width column grid: every card starts on a shared column line and
    /// every title in a row starts on the same baseline, in both orientations.
    private var downloadsGrid: some View {
        let items = visibleDownloads
        let posters = items.map { localPosterImage(for: $0) }
        let artworks = zip(items, posters).map { gridArtwork(for: $0.0, poster: $0.1) }
        let arrangement = DownloadsGridLayoutPolicy.arrange(
            artworks,
            availableWidth: gridAvailableWidth,
            metrics: gridMetrics
        )

        // A plain VStack: the grid is already one child of the outer LazyVStack, and
        // building every row keeps all cards (and their test hooks) in the hierarchy.
        return VStack(alignment: .leading, spacing: gridRowSpacing) {
            ForEach(Array(arrangement.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: arrangement.columnSpacing) {
                    ForEach(row.placements, id: \.index) { placement in
                        gridCell(
                            items[placement.index],
                            poster: posters[placement.index],
                            placement: placement,
                            posterAreaHeight: row.posterAreaHeight
                        )
                    }
                }
                .padding(.leading, arrangement.leadingInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("downloads.grid")
    }

    private func gridArtwork(
        for item: DownloadItem,
        poster: PlatformImage?
    ) -> DownloadsGridLayoutPolicy.Artwork {
        // "Other Videos" libraries (Plex agent = "none": personal media, YouTube, home videos)
        // use type=movie but store landscape thumbnails, not portrait movie posters. The only
        // reliable signal at display time is the downloaded poster's aspect ratio. If the poster
        // is wider than tall, render landscape even though prefersPortraitArtwork is true.
        // Note: clip-type items (Plex extras/trailers) can't be downloaded — enqueueItem filters
        // them — so type-based landscape logic is irrelevant for real download items.
        let posterIsLandscape = poster.map { $0.size.width > $0.size.height } ?? false
        if !posterIsLandscape && item.metadata.prefersPortraitArtwork {
            return .portrait
        }

        return .landscape(
            aspectRatio: DownloadsArtworkLayoutPolicy.displayAspectRatio(
                for: .landscape,
                imageSize: poster?.size
            )
        )
    }

    private func gridCell(
        _ item: DownloadItem,
        poster: PlatformImage?,
        placement: DownloadsGridLayoutPolicy.Placement,
        posterAreaHeight: CGFloat
    ) -> some View {
        let posterSize = placement.posterSize
        let posterTopInset = max(posterAreaHeight - posterSize.height, 0)

        return VStack(alignment: .leading, spacing: 6) {
            posterCell(
                item,
                poster: poster,
                posterSize: posterSize,
                cellWidth: placement.cellWidth,
                posterAreaHeight: posterAreaHeight
            )
            metadataLabels(for: item, titleLineLimit: 2)
                .frame(width: placement.cellWidth, height: gridTextHeight, alignment: .topLeading)
        }
        .frame(width: placement.cellWidth, alignment: .topLeading)
        // Accessibility hooks outside the Button so XCTest finds them as .other elements
        // (Button labels are not traversable as otherElements / descendants in iOS 26).
        // Thumbnail: the rendered poster frame (artwork is bottom-aligned in the row's
        // shared poster area, so the hook is offset by the same top inset).
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: posterSize.width, height: posterSize.height)
                .accessibilityIdentifier("downloads.thumbnail.\(item.id)")
                .allowsHitTesting(false)
                .padding(.top, posterTopInset)
        }
        // Progress: placed at the bottom of the card (non-overlapping with thumbnail above)
        // so iOS 26 doesn't merge the two accessibility elements. Width = track width.
        // Unconditional: this is a geometry hook for testing the progress track layout
        // (width must fit within the thumbnail). The progress bar inside the Button shows
        // only when downloading; this overlay is always present so restoreRunningTasks()
        // resetting status to .failed doesn't make the element disappear before tests query it.
        .overlay(alignment: .bottomLeading) {
            Color.clear
                .frame(width: max(posterSize.width - 8, 0), height: gridTextHeight)
                .accessibilityIdentifier("downloads.progress.\(item.id)")
                .allowsHitTesting(false)
        }
    }

    private func posterCell(
        _ item: DownloadItem,
        poster: PlatformImage?,
        posterSize: CGSize,
        cellWidth: CGFloat,
        posterAreaHeight: CGFloat
    ) -> some View {
        return Button {
            guard item.isPlayable, accessPolicy.decision(for: item) == .allowed else { return }
            selectedDownload = item
        } label: {
            // Every card in a row shares the row's poster-area height so titles align;
            // shorter (landscape) artwork sits on the bottom edge, directly above its title.
            Color.clear
                .frame(width: cellWidth, height: posterAreaHeight)
                .overlay(alignment: .bottomLeading) {
                    posterArtwork(
                        for: item,
                        poster: poster,
                        posterSize: posterSize
                    )
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(item.isPlayable ? 1 : 0.85)
    }

    private func listRow(_ item: DownloadItem) -> some View {
        let isPortrait = item.metadata.prefersPortraitArtwork
        let posterSize = isPortrait ? CGSize(width: 45, height: 68) : CGSize(width: 78, height: 44)

        return Button {
            guard item.isPlayable, accessPolicy.decision(for: item) == .allowed else { return }
            selectedDownload = item
        } label: {
            HStack(alignment: .center, spacing: 12) {
                // Fixed-width slot keeps every title on the same leading edge whether
                // the artwork is portrait or landscape.
                posterImage(for: item)
                    .frame(width: posterSize.width, height: posterSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(width: listArtworkSlotSize.width, height: listArtworkSlotSize.height)

                VStack(alignment: .leading, spacing: 4) {
                    metadataLabels(for: item, titleLineLimit: 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 4) {
                    if let downloadedSize = downloadedSize(for: item) {
                        Text(formattedBytes(downloadedSize))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }

                    if item.isPlayable {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(minWidth: item.isPlayable ? 40 : nil, maxHeight: .infinity, alignment: .center)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(item.isPlayable ? 1 : 0.85)
    }

    private func metadataLabels(for item: DownloadItem, titleLineLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.metadata.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(titleLineLimit)
                .multilineTextAlignment(.leading)

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
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
            }

            if let tertiary = tertiaryLabel(for: item) {
                Text(tertiary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.status == .failed ? Color.red : Color.accentColor)
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
        item.status == .completed ? nil : item.plinxStatusText
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

    private func downloadedSize(for item: DownloadItem) -> Int64? {
        if let fileSize = item.metadata.fileSize, fileSize > 0 {
            return fileSize
        }

        return item.bytesWritten > 0 ? item.bytesWritten : nil
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

            if item.status == .downloading || item.status == .preparing {
                VStack {
                    Spacer()
                    ProgressView(
                        value: item.status == .preparing
                            ? item.preparationProgress
                            : item.progress
                    )
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                }
            }
        }
        .frame(width: posterSize.width, height: posterSize.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            if item.status == .downloading
                || item.status == .queued
                || item.status == .deciding
                || item.status == .preparing
            {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
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
                .fill(Color.white.opacity(0.08))
                .overlay {
                    Image(systemName: "film")
                        .foregroundStyle(.white.opacity(0.45))
                        .font(.title3)
                }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("downloads.empty.title", tableName: "Plinx")
                .font(.headline)
                .foregroundStyle(.white)
            Text("downloads.empty.message", tableName: "Plinx")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 32)
    }
}

// MARK: - Manage view wrapper

/// Parent-gated download management sheet (status, quality details, delete)
/// on the Plinx dark shell with the standard sheet header.
@MainActor
struct PlinxDownloadsManageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(SessionManager.self) private var sessionManager
    @Environment(DownloadOwnershipStore.self) private var downloadOwnershipStore
    @Environment(\.safetyPolicy) private var safetyPolicy

    private var visibleDownloads: [DownloadItem] {
        DownloadAccessPolicy(
            safetyPolicy: safetyPolicy,
            currentIdentity: sessionManager.plinxDownloadOwnerIdentity,
            ownershipStore: downloadOwnershipStore
        ).filter(downloadManager.sortedItems)
    }

    var body: some View {
        List {
            if visibleDownloads.isEmpty {
                Text("downloads.empty.message", tableName: "Plinx")
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                ForEach(visibleDownloads) { item in
                    manageRow(item)
                }
            }
        }
        #if os(tvOS)
        .listStyle(.plain)
        #else
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        #endif
        .background(Color.appBackground.ignoresSafeArea())
        .tint(.accentColor)
        .safeAreaInset(edge: .top, spacing: 0) {
            PlinxSheetHeader(
                title: Text("downloads.manage.title", tableName: "Plinx"),
                onClose: { dismiss() }
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        #if !os(tvOS)
        .presentationBackground(Color.appBackground)
        #endif
        .task {
            await downloadManager.recheckNetworkStatus()
        }
    }

    private func manageRow(_ item: DownloadItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.metadata.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(item.plinxStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.status == .failed ? Color.red : Color.accentColor)

                if let qualitySummary = qualitySummary(for: item) {
                    Text(qualitySummary)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }

                if let sizeSummary = sizeSummary(for: item) {
                    Text(sizeSummary)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }

                if let reason = qualityReason(for: item) {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(
                            item.qualityResolutionReason == .serverRejectedProfile
                                ? Color.red
                                : Color.white.opacity(0.65)
                        )
                        .lineLimit(2)
                }

                if item.status == .failed, let errorMessage = item.errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if item.status.isActive {
                ProgressView(
                    value: item.status == .preparing
                        ? item.preparationProgress
                        : item.progress
                )
                .tint(.accentColor)
                .frame(width: 90)
            }

            Button(role: .destructive) {
                Task { await downloadManager.delete(item) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.red.opacity(0.14))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("common.actions.delete", tableName: "Plinx"))
            .accessibilityIdentifier("downloads.manage.delete.\(item.id)")
        }
        .padding(.vertical, 4)
    }

    private func qualitySummary(for item: DownloadItem) -> String? {
        guard let requestedQuality = item.requestedQuality else { return nil }
        let effectiveQuality = item.effectiveQuality ?? requestedQuality
        return String.localizedStringWithFormat(
            NSLocalizedString("downloads.manage.quality", tableName: "Plinx", comment: ""),
            requestedQuality.title,
            effectiveQuality.title
        )
    }

    private func sizeSummary(for item: DownloadItem) -> String? {
        var values: [String] = []
        if let sourceFileSize = item.sourceFileSize, sourceFileSize > 0 {
            values.append(String.localizedStringWithFormat(
                NSLocalizedString("downloads.manage.sourceSize", tableName: "Plinx", comment: ""),
                Self.formattedBytes(sourceFileSize)
            ))
        }
        if let estimatedOutputBytes = item.estimatedOutputBytes, estimatedOutputBytes > 0 {
            values.append(String.localizedStringWithFormat(
                NSLocalizedString("downloads.manage.estimatedSize", tableName: "Plinx", comment: ""),
                Self.formattedBytes(estimatedOutputBytes)
            ))
        }
        if let finalSize = item.metadata.fileSize, finalSize > 0 {
            values.append(String.localizedStringWithFormat(
                NSLocalizedString("downloads.manage.finalSize", tableName: "Plinx", comment: ""),
                Self.formattedBytes(finalSize)
            ))
            if let sourceFileSize = item.sourceFileSize, sourceFileSize > 0, finalSize < sourceFileSize {
                let percent = Int(((1 - Double(finalSize) / Double(sourceFileSize)) * 100).rounded())
                values.append(String.localizedStringWithFormat(
                    NSLocalizedString("downloads.manage.savings", tableName: "Plinx", comment: ""),
                    Int64(percent)
                ))
            }
        }
        return values.isEmpty ? nil : values.joined(separator: " • ")
    }

    private func qualityReason(for item: DownloadItem) -> String? {
        guard let reason = item.qualityResolutionReason, reason != .requested else { return nil }
        let key = switch reason {
        case .requested:
            "downloads.manage.reason.requested"
        case .originalIsSmaller:
            "downloads.manage.reason.originalSmaller"
        case .insufficientSavings:
            "downloads.manage.reason.insufficientSavings"
        case .serverRejectedProfile:
            "downloads.manage.reason.serverRejected"
        case .actualSavingsTooSmall:
            "downloads.manage.reason.actualSavings"
        }
        return NSLocalizedString(key, tableName: "Plinx", comment: "")
    }

    private static func formattedBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
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

private extension DownloadItem {
    /// Localized, user-facing download status shared by the grid, list and
    /// manage views.
    var plinxStatusText: String {
        switch status {
        case .queued:
            return NSLocalizedString("downloads.status.queued", tableName: "Plinx", comment: "")
        case .deciding:
            return NSLocalizedString("downloads.status.deciding", tableName: "Plinx", comment: "")
        case .preparing:
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    preparationProgress == nil
                        ? "downloads.status.preparing %lld"
                        : "downloads.status.transcoding %lld",
                    tableName: "Plinx",
                    comment: ""
                ),
                Int64(((preparationProgress ?? 0) * 100).rounded())
            )
        case .downloading:
            return String.localizedStringWithFormat(
                NSLocalizedString("downloads.status.downloading %lld", tableName: "Plinx", comment: ""),
                Int64((progress * 100).rounded())
            )
        case .completed:
            return NSLocalizedString("downloads.status.completed", tableName: "Plinx", comment: "")
        case .failed:
            return NSLocalizedString("downloads.status.failed", tableName: "Plinx", comment: "")
        }
    }
}
