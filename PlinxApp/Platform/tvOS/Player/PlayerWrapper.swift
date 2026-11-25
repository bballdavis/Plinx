import SwiftUI

struct PlayerWrapper: View {
    let viewModel: PlayerViewModel
    let onExit: () -> Void
    let showsBufferingOverlay: Bool
    let isPlaybackAuthorized: @MainActor (MediaItem) -> Bool
    let onCurrentMediaChange: @MainActor (MediaItem?) -> Void

    /// The default authorization is the shared safety boundary, so a caller that passes nothing still plays only
    /// what the active policy allows.
    init(
        viewModel: PlayerViewModel,
        onExit: @escaping () -> Void,
        showsBufferingOverlay: Bool = true,
        isPlaybackAuthorized: @escaping @MainActor (MediaItem) -> Bool = { ContentSafetyGate.shared.isAllowed($0) },
        onCurrentMediaChange: @escaping @MainActor (MediaItem?) -> Void = { _ in },
    ) {
        self.viewModel = viewModel
        self.onExit = onExit
        self.showsBufferingOverlay = showsBufferingOverlay
        self.isPlaybackAuthorized = isPlaybackAuthorized
        self.onCurrentMediaChange = onCurrentMediaChange
    }

    var body: some View {
        // Plinx always uses its own player chrome and timeline: the system controls style (#413) bypasses both.
        PlayerView(
            viewModel: viewModel,
            controlsStyle: .classic,
            onExit: onExit,
            showsBufferingOverlay: showsBufferingOverlay,
            isPlaybackAuthorized: isPlaybackAuthorized,
            onCurrentMediaChange: onCurrentMediaChange,
        )
    }
}
