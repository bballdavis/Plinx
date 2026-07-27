import SwiftUI
import PlinxCore

struct PlinxPlaylistDetailView: View {
    @State var viewModel: SafePlaylistDetailViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onPlay: (MediaItem) -> Void

    @Environment(\.safetyPolicy) private var safetyPolicy

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                PlinxBrandedLoadingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                ContentUnavailableView(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("common.errors.tryAgainLater")
                )
            } else if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "library.browse.empty.title",
                    systemImage: "lock.shield.fill",
                    description: Text("media.playlist.noAllowedItems", tableName: "Plinx")
                )
            } else {
                playlistContent
            }
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: safetyPolicy) { _, newPolicy in
            viewModel.updatePolicy(newPolicy)
        }
    }

    @ViewBuilder
    private var playlistContent: some View {
        #if os(tvOS)
        PlaylistDetailTVView(
            viewModel: viewModel.rawViewModel,
            onSelectMedia: onSelectMedia,
            onPlay: { _ in play(shuffled: false) },
            onShuffle: { _ in play(shuffled: true) }
        )
        #else
        PlaylistDetailView(
            viewModel: viewModel.rawViewModel,
            onSelectMedia: onSelectMedia,
            onPlay: { _ in play(shuffled: false) },
            onShuffle: { _ in play(shuffled: true) }
        )
        #endif
    }

    private func play(shuffled: Bool) {
        guard let item = viewModel.playbackItem(shuffled: shuffled) else { return }
        onPlay(item)
    }
}
