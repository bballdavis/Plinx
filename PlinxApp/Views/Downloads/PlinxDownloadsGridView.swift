import SwiftUI
import UIKit
import Foundation

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

    // 7-column grid — ~25% smaller thumbs than the previous 5-column layout
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if downloadManager.isOffline {
                    Label("downloads.offline.banner", systemImage: "wifi.slash")
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
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(downloadManager.sortedItems) { item in
                                gridCell(item)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 120)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(downloadManager.sortedItems) { item in
                                listRow(item)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 120)
                    }
                }
            }
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
    }

    // MARK: - Header

    private var titleRow: some View {
        ZStack {
            Text("tabs.downloads")
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
        VStack(alignment: .leading, spacing: 6) {
            posterCell(item)
            metadataLabels(for: item, titleLineLimit: 1)
        }
    }

    private func posterCell(_ item: DownloadItem) -> some View {
        let isPortrait = portraitTypes.contains(item.metadata.type)
        let ratio: CGFloat = isPortrait ? 2.0 / 3.0 : 16.0 / 9.0

        return Button {
            guard item.isPlayable else { return }
            selectedDownload = item
        } label: {
            ZStack(alignment: .bottom) {
                posterImage(for: item)
                    .aspectRatio(ratio, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                // Download-in-progress indicator
                if item.status == .downloading || item.status == .queued {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
                if item.status == .downloading {
                    VStack {
                        Spacer()
                        ProgressView(value: item.progress)
                            .progressViewStyle(.linear)
                            .tint(Color.accentColor)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 4)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(item.isPlayable ? 1 : 0.85)
    }

    private func listRow(_ item: DownloadItem) -> some View {
        let isPortrait = portraitTypes.contains(item.metadata.type)
        let posterSize = isPortrait ? CGSize(width: 45, height: 68) : CGSize(width: 78, height: 44)

        return Button {
            guard item.isPlayable else { return }
            selectedDownload = item
        } label: {
            HStack(alignment: .top, spacing: 12) {
                posterImage(for: item)
                    .frame(width: posterSize.width, height: posterSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    metadataLabels(for: item, titleLineLimit: 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if item.isPlayable {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 2)
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

            if let secondary = secondaryLabel(for: item) {
                Text(secondary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let tertiary = tertiaryLabel(for: item) {
                Text(tertiary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func secondaryLabel(for item: DownloadItem) -> String? {
        switch item.metadata.type {
        case .episode:
            return item.metadata.subtitle
        case .movie:
            return joinedMeta([item.metadata.year.map(String.init), item.metadata.contentRating])
        case .season:
            return item.metadata.parentTitle
        case .show:
            return joinedMeta([item.metadata.contentRating, item.metadata.year.map(String.init)])
        default:
            return item.metadata.subtitle
        }
    }

    private func tertiaryLabel(for item: DownloadItem) -> String? {
        switch item.status {
        case .queued:
            return "Queued"
        case .downloading:
            return "Downloading \(Int((item.progress * 100).rounded()))%"
        case .completed:
            return nil
        case .failed:
            return "Download failed"
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
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var portraitTypes: Set<PlexItemType> {
        [.movie, .show, .season, .episode]
    }

    @ViewBuilder
    private func posterImage(for item: DownloadItem) -> some View {
        if let posterURL = downloadManager.localPosterURL(for: item),
           let uiImage = UIImage(contentsOfFile: posterURL.path)
        {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
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
            Text("downloads.empty.title")
                .font(.headline)
            Text("downloads.empty.message")
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
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 52, height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                    )
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}
