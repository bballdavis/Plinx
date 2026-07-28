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
    @Environment(\.safetyPolicy) private var safetyPolicy

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlinxPlayerPlaybackView(
                viewModel: viewModel,
                onExit: {
                    isPresented = false
                },
                isPlaybackAuthorized: { item in
                    PlinxContentAuthorization.isAllowed(item, policy: safetyPolicy)
                }
            )
            .ignoresSafeArea()

            overlayControls
        }
        .animation(.easeInOut(duration: 0.18), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.18), value: viewModel.isBuffering)
        #if !os(tvOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        #endif
    }

    // MARK: - Overlay controls

    private var overlayControls: some View {
        VStack {
            HStack {
                closeButton
                Spacer()
                contentRatingBadge
            }
            .padding(.horizontal, 10)
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
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.brandPrimary.opacity(0.42), lineWidth: 1)
                    )
                    .frame(width: 66, height: 66)
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Color.brandPrimary.opacity(0.14), radius: 12, x: 0, y: 6)
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

/// Plinx-owned presentation layer around Strimr's playback engine.
///
/// Strimr keeps transport and controls; Plinx owns the branded buffering
/// presentation and disables the upstream spinner through a default-safe seam.
struct PlinxPlayerPlaybackView: View {
    let viewModel: PlayerViewModel
    let onExit: () -> Void
    let isPlaybackAuthorized: (PlexItem) -> Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            #if os(tvOS)
            PlayerTVWrapper(
                viewModel: viewModel,
                onExit: onExit,
                showsBufferingOverlay: false,
                isPlaybackAuthorized: isPlaybackAuthorized
            )
            #else
            PlayerWrapper(
                viewModel: viewModel,
                showsBufferingOverlay: false,
                isPlaybackAuthorized: isPlaybackAuthorized
            )
            .onDisappear(perform: onExit)
            #endif

            if viewModel.isLoading || viewModel.isBuffering {
                PlinxVideoBufferingOverlay()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.18), value: viewModel.isBuffering)
    }
}

struct PlinxVideoBufferingOverlay: View {
    var body: some View {
        PlinxLoadingIndicator(
            size: .regular,
            surface: .video,
            accessibilityLabel: "player.status.buffering",
            accessibilityIdentifier: "player.buffering.plinx"
        )
        .padding(28)
        .allowsHitTesting(false)
    }
}
