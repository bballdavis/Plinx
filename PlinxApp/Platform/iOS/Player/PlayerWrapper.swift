import SwiftUI

struct PlayerWrapper: View {
    let viewModel: PlayerViewModel
    let showsBufferingOverlay: Bool
    let isPlaybackAuthorized: @MainActor (MediaItem) -> Bool

    /// The default authorization is the shared safety boundary, so a caller that passes nothing still plays only
    /// what the active policy allows.
    init(
        viewModel: PlayerViewModel,
        showsBufferingOverlay: Bool = true,
        isPlaybackAuthorized: @escaping @MainActor (MediaItem) -> Bool = { ContentSafetyGate.shared.isAllowed($0) },
    ) {
        self.viewModel = viewModel
        self.showsBufferingOverlay = showsBufferingOverlay
        self.isPlaybackAuthorized = isPlaybackAuthorized
    }

    var body: some View {
        PlayerView(
            viewModel: viewModel,
            showsBufferingOverlay: showsBufferingOverlay,
            isPlaybackAuthorized: isPlaybackAuthorized,
        )
        .transition(.opacity)
    }
}
