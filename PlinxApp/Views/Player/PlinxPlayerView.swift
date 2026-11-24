import PlinxUI
import PlinxCore
import SwiftUI

/// Plinx-styled player screen.
///
/// Wraps Strimr's `PlayerWrapper` with kid-safe UI:
/// - Plinx-sized player overlay header
/// - Branded buffering and loading presentation
///
/// The core playback is still delegated to `PlayerWrapper`/`PlayerViewModel`
/// from Strimr. A full bespoke player is planned for Phase 3.
struct PlinxPlayerView: View {
    @Binding var isPresented: Bool
    let viewModel: PlayerViewModel
    let onRequestMoreInfo: (MediaItem) -> Void

    @Environment(\.safetyPolicy) private var safetyPolicy
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(PlinxWatchStatusStore.self) private var watchStatusStore
    @State private var quickActionMedia: MediaItem?
    @State private var quickActionErrorMessage: String?

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
            #if os(tvOS)
            .plinxQuickActionLongPress {
                guard let media = viewModel.media else { return }
                presentQuickActions(for: media)
            }
            .allowsHitTesting(quickActionMedia == nil)
            .accessibilityHidden(quickActionMedia != nil)
            #endif

            #if !os(tvOS)
            if let media = viewModel.media,
               PlinxContentAuthorization.isAllowed(media, policy: safetyPolicy)
            {
                playerQuickActionsButton(for: media)
                    .allowsHitTesting(quickActionMedia == nil)
                    .accessibilityHidden(quickActionMedia != nil)
            }
            #endif

            if let media = quickActionMedia {
                PlinxQuickActionMenu(
                    title: media.title,
                    options: playerQuickActionOptions(for: media),
                    onDismiss: { quickActionMedia = nil }
                )
            }
        }
        #if !os(tvOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        #endif
        .alert(
            Text("common.error.actionFailed", tableName: "Plinx"),
            isPresented: Binding(
                get: { quickActionErrorMessage != nil },
                set: { if !$0 { quickActionErrorMessage = nil } }
            )
        ) {
            Button(String(localized: "common.actions.ok", table: "Plinx"), role: .cancel) {}
        } message: {
            Text(quickActionErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private func playerQuickActionsButton(for media: MediaItem) -> some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    presentQuickActions(for: media)
                } label: {
                    Label(
                        String(localized: "quickActions.moreActions", table: "Plinx"),
                        systemImage: "ellipsis.circle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("player.moreActions")
            }
            Spacer()
        }
        .padding(.horizontal, 40)
        .padding(.top, 42)
    }

    private func presentQuickActions(for media: MediaItem) {
        guard viewModel.media?.id == media.id,
              PlinxContentAuthorization.isAllowed(media, policy: safetyPolicy)
        else {
            quickActionErrorMessage = String(localized: "media.unavailable.title", table: "Plinx")
            return
        }
        quickActionMedia = media
    }

    private func playerQuickActionOptions(for media: MediaItem) -> [PlinxQuickActionOption] {
        [
            PlinxQuickActionOption(
                id: "toggle-watched",
                title: watchStatusStore.isWatched(media)
                    ? String(localized: "quickActions.markUnwatched", table: "Plinx")
                    : String(localized: "quickActions.markWatched", table: "Plinx"),
                systemImage: watchStatusStore.isWatched(media) ? "checkmark.circle.fill" : "checkmark.circle",
                role: nil,
                action: {
                    Task { await toggleWatched(media) }
                }
            ),
            PlinxQuickActionOption(
                id: "go-details",
                title: String(localized: "quickActions.moreInfo", table: "Plinx"),
                systemImage: "info.circle",
                role: nil,
                action: {
                    guard PlinxContentAuthorization.isAllowed(media, policy: safetyPolicy) else {
                        quickActionErrorMessage = String(localized: "media.unavailable.title", table: "Plinx")
                        return
                    }
                    onRequestMoreInfo(media)
                    isPresented = false
                }
            ),
        ]
    }

    private func toggleWatched(_ media: MediaItem) async {
        guard PlinxContentAuthorization.isAllowed(media, policy: safetyPolicy) else {
            quickActionErrorMessage = String(localized: "media.unavailable.title", table: "Plinx")
            return
        }
        do {
            _ = try await watchStatusStore.toggle(media, context: plexApiContext, isAllowed: true)
        } catch {
            quickActionErrorMessage = error.localizedDescription
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
        .buttonStyle(PlinxPlayerExitButtonStyle())
        .accessibilityLabel(String(localized: "common.actions.back", table: "Plinx"))
        .accessibilityIdentifier("player.back")
    }
}

private struct PlinxPlayerExitButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .plinxFocusSurface(isSelected: false, isFocused: isFocused)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.18),
                value: configuration.isPressed
            )
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

            PlinxVideoBufferingOverlay()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .opacity(showsLoadingOverlay ? 1 : 0)
                .accessibilityHidden(!showsLoadingOverlay)
                .animation(.easeInOut(duration: 0.18), value: showsLoadingOverlay)
        }
    }

    private var showsLoadingOverlay: Bool {
        viewModel.isLoading || viewModel.isBuffering
    }
}

struct PlinxVideoBufferingOverlay: View {
    var body: some View {
        PlinxLoadingStateView(
            role: .playback,
            accessibilityLabel: LocalizedStringResource(
                "player.status.buffering",
                table: "Plinx"
            ),
            accessibilityIdentifier: "player.buffering.plinx"
        )
        .padding(28)
        .allowsHitTesting(false)
    }
}

struct PlinxPlaybackLoadingView: View {
    let onExit: () -> Void
    #if os(tvOS)
    @Namespace private var focusNamespace
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlinxLoadingStateView(
                role: .playback,
                label: LocalizedStringResource(
                    "player.status.loading",
                    table: "Plinx"
                ),
                accessibilityLabel: LocalizedStringResource(
                    "player.status.loading",
                    table: "Plinx"
                ),
                accessibilityIdentifier: "player.loading.plinx"
            )
            .allowsHitTesting(false)

            VStack {
                HStack {
                    PlinxPlayerExitButton(action: onExit)
                    #if os(tvOS)
                        .prefersDefaultFocus(true, in: focusNamespace)
                    #endif
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
        #else
        .focusScope(focusNamespace)
        .onExitCommand(perform: onExit)
        #endif
    }
}

struct PlinxPlaybackPresentationView: View {
    @EnvironmentObject private var mainCoordinator: MainCoordinator
    @EnvironmentObject private var playbackLaunchCoordinator: PlaybackLaunchCoordinator
    @Environment(PlexAPIContext.self) private var plexApiContext
    @State private var playerViewModel: PlayerViewModel?
    let onRequestMoreInfo: (MediaItem) -> Void

    var body: some View {
        Group {
            if let playerViewModel {
                PlinxPlayerView(
                    isPresented: playerPresentationBinding,
                    viewModel: playerViewModel,
                    onRequestMoreInfo: onRequestMoreInfo
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
