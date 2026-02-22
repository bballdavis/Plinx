import SwiftUI
import PlinxUI

/// Plinx-styled player screen.
///
/// Wraps Strimr's `PlayerWrapper` with kid-safe UI:
/// - Top-left ✕ close button (YouTube-style)
/// - Oversized centre play/pause (shown when paused)
/// - Progress bar with fat-finger scrubber
/// - Swipe-up "Related Videos" tray (Phase 3 — placeholder)
///
/// The core playback is still delegated to `PlayerWrapper`/`PlayerViewModel`
/// from Strimr. A full bespoke player is planned for Phase 3.
struct PlinxPlayerView: View {
    @Binding var isPresented: Bool
    let viewModel: PlayerViewModel

    @Environment(\.plinxTheme) private var theme

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Strimr's proven player engine (MPVKit-backed)
            PlayerWrapper(viewModel: viewModel)
                .ignoresSafeArea()

            overlayControls
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Overlay controls

    private var overlayControls: some View {
        VStack {
            HStack {
                closeButton
                Spacer()
                contentRatingBadge
            }
            .padding(.horizontal, 20)
            .padding(.top, 52)

            Spacer()
        }
    }

    private var closeButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isPresented = false
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                    .frame(width: 44, height: 44)
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }

    private var contentRatingBadge: some View {
        Group {
            if let rating = viewModel.media?.contentRating {
                Text(rating)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
                    )
                    .opacity(0.85)
            }
        }
    }
}
