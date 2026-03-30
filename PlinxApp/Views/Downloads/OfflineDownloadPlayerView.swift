import SwiftUI

struct OfflineDownloadPlayerView: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(PlexAPIContext.self) private var context
    @Environment(\.dismiss) private var dismiss

    let item: DownloadItem

    var body: some View {
        if let localURL = downloadManager.localVideoURL(for: item) {
            OfflineActivePlayerView(
                item: item,
                localMedia: downloadManager.localMediaItem(for: item),
                localPlaybackURL: localURL,
                context: context,
                onPlaybackEnded: { position, duration, didFinish in
                    downloadManager.updatePlaybackState(
                        forDownloadID: item.id,
                        position: position,
                        duration: duration,
                        didFinish: didFinish
                    )
                }
            )
        } else {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title)
                        .foregroundStyle(.orange)

                    Text("Downloaded video unavailable")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("This download does not currently have a local file to play.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(24)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Circle().fill(.white.opacity(0.15)))
                }
                .padding(.top, 56)
                .padding(.trailing, 20)
            }
        }
    }

}

private struct OfflineActivePlayerView: View {
    let item: DownloadItem
    let localMedia: MediaItem
    let localPlaybackURL: URL
    let context: PlexAPIContext
    let onPlaybackEnded: (_ position: TimeInterval, _ duration: TimeInterval?, _ didFinish: Bool) -> Void

    @State private var playerViewModel: PlayerViewModel

    init(
        item: DownloadItem,
        localMedia: MediaItem,
        localPlaybackURL: URL,
        context: PlexAPIContext,
        onPlaybackEnded: @escaping (_ position: TimeInterval, _ duration: TimeInterval?, _ didFinish: Bool) -> Void
    ) {
        self.item = item
        self.localMedia = localMedia
        self.localPlaybackURL = localPlaybackURL
        self.context = context
        self.onPlaybackEnded = onPlaybackEnded
        _playerViewModel = State(initialValue: PlayerViewModel(
            localMedia: localMedia,
            localPlaybackURL: localPlaybackURL,
            context: context
        ))
    }

    var body: some View {
        PlayerWrapper(viewModel: playerViewModel)
            .onDisappear {
                onPlaybackEnded(
                    playerViewModel.position,
                    playerViewModel.duration ?? item.metadata.duration,
                    didFinishPlayback(viewModel: playerViewModel)
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