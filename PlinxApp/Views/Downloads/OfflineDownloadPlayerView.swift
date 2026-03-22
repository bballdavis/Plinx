import SwiftUI

struct OfflineDownloadPlayerView: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(PlexAPIContext.self) private var context

    let item: DownloadItem

    @State private var playerViewModel: PlayerViewModel?

    var body: some View {
        Group {
            if let playerViewModel {
                PlayerWrapper(viewModel: playerViewModel)
            } else {
                PlinxBrandedLoadingView(
                    preferredLogoAssetName: "LogoStackedFullWhite",
                    showsProgressView: true,
                    fillsBackground: true
                )
                .task(id: item.id) {
                    guard playerViewModel == nil else { return }
                    guard let localURL = downloadManager.localVideoURL(for: item) else { return }
                    playerViewModel = PlayerViewModel(
                        localMedia: downloadManager.localMediaItem(for: item),
                        localPlaybackURL: localURL,
                        context: context,
                    )
                }
            }
        }
        .onDisappear {
            guard let playerViewModel else { return }
            downloadManager.updatePlaybackState(
                forDownloadID: item.id,
                position: playerViewModel.position,
                duration: playerViewModel.duration ?? item.metadata.duration,
                didFinish: didFinishPlayback(viewModel: playerViewModel)
            )
        }
    }

    private func didFinishPlayback(viewModel: PlayerViewModel) -> Bool {
        let position = max(0, viewModel.position)
        guard let duration = viewModel.duration ?? item.metadata.duration, duration > 0 else {
            return false
        }
        return position >= max(duration * 0.95, duration - 60)
    }
}