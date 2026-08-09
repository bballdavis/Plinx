import SwiftUI
import PlinxUI

/// Plinx-styled player screen.
///
/// Wraps Strimr's `PlayerWrapper` with kid-safe UI:
/// - Top-left oversized back button
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
        PlinxPlayerExitButton {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isPresented = false
            }
        }
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

struct PlinxPlayerExitButton: View {
    let action: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var buttonSize: CGFloat {
        PlinxPlayerControlLayout.exitButtonSize(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass
        )
    }

    private var iconSize: CGFloat {
        PlinxPlayerControlLayout.exitIconSize(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass
        )
    }

    var body: some View {
        Button(action: action) {
            let chrome = RoundedRectangle(
                cornerRadius: buttonSize * 0.27,
                style: .continuous
            )
            Image(systemName: "chevron.left")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: buttonSize, height: buttonSize)
                .background(chrome.fill(.ultraThinMaterial))
                .overlay(
                    chrome.stroke(
                        Color.brandPrimary.opacity(0.52),
                        lineWidth: max(2, buttonSize / 40)
                    )
                )
                .shadow(
                    color: Color.brandPrimary.opacity(0.18),
                    radius: buttonSize * 0.18,
                    x: 0,
                    y: buttonSize * 0.09
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "common.actions.back"))
        .accessibilityIdentifier("player.back")
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
            size: .hero,
            surface: .video,
            accessibilityLabel: "player.status.buffering",
            accessibilityIdentifier: "player.buffering.plinx"
        )
        .padding(28)
        .allowsHitTesting(false)
    }
}

struct PlinxPlaybackLoadingView: View {
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlinxLoadingIndicator(
                size: .hero,
                surface: .video,
                label: "player.status.loading",
                accessibilityLabel: "player.status.loading",
                accessibilityIdentifier: "player.loading.plinx"
            )
            .allowsHitTesting(false)

            VStack {
                HStack {
                    PlinxPlayerExitButton(action: onExit)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 52)

                Spacer()
            }
        }
        #if !os(tvOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        #endif
    }
}

struct PlinxPlaybackPresentationView: View {
    @EnvironmentObject private var mainCoordinator: MainCoordinator
    @EnvironmentObject private var playbackLaunchCoordinator: PlaybackLaunchCoordinator
    @Environment(PlexAPIContext.self) private var plexApiContext
    @State private var playerViewModel: PlayerViewModel?

    var body: some View {
        Group {
            if let playerViewModel {
                PlinxPlayerView(
                    isPresented: playerPresentationBinding,
                    viewModel: playerViewModel
                )
            } else {
                PlinxPlaybackLoadingView {
                    playbackLaunchCoordinator.cancelPendingLaunch()
                    mainCoordinator.resetPlayer()
                }
            }
        }
        .task(id: mainCoordinator.selectedPlayQueue?.id) {
            guard let playQueue = mainCoordinator.selectedPlayQueue else {
                playerViewModel = nil
                return
            }

            playerViewModel = PlayerViewModel(
                playQueue: playQueue,
                context: plexApiContext,
                shouldResumeFromOffset: mainCoordinator.shouldResumeFromOffset
            )
        }
    }

    private var playerPresentationBinding: Binding<Bool> {
        Binding(
            get: { mainCoordinator.selectedPlayQueue != nil },
            set: { isPresented in
                if !isPresented {
                    mainCoordinator.resetPlayer()
                }
            }
        )
    }
}
