import SwiftUI
import UIKit

/// The main downloads tab: a 5-column poster grid with an Edit button that
/// opens the download management list (storage info, delete, etc.).
@MainActor
struct PlinxDownloadsGridView: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(PlexAPIContext.self) private var context
    @State private var selectedDownload: DownloadItem?
    @State private var showManage = false

    // 5-column grid matching the library browse layout
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

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
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(downloadManager.sortedItems) { item in
                            posterCell(item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 120)
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
                Spacer()
                Button {
                    showManage = true
                } label: {
                    Image(systemName: "pencil")
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
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - Grid cells

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
