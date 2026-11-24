import PlinxUI
import PlinxCore
import SwiftUI
#if os(iOS)
import AetherEngine
import AVFoundation
import UIKit
#endif

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
            // PlayerSurfaceView extends the video itself to every edge. Keep
            // the wrapper's safe area so controls avoid the Duo status region
            // and the closed display's camera and home indicator.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .plinxVideoPresentation()
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container)
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

#if os(iOS)
private struct PlinxVideoFillKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}

extension EnvironmentValues {
    var plinxVideoFill: Binding<Bool>? {
        get { self[PlinxVideoFillKey.self] }
        set { self[PlinxVideoFillKey.self] = newValue }
    }
}

extension View {
    func plinxVideoPresentation() -> some View {
        modifier(PlinxVideoPresentationModifier())
    }
}

private struct PlinxVideoPresentationModifier: ViewModifier {
    // The player owns this state, rather than its auto-hiding controls.
    @State private var fillsScreen = false

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            content
                .environment(\.plinxVideoFill, isLandscape ? $fillsScreen : nil)
                .background {
                    PlinxVideoGravityBridge(fillsScreen: isLandscape && fillsScreen)
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        }
    }
}

/// Decorates Aether's public render view using public AVFoundation layer APIs.
/// Keeping this in Plinx avoids changing Strimr's private engine ownership.
/// Observe layer replacement and gravity resets so native/software dispatch
/// changes and subsequent queue items retain the session's presentation mode.
@MainActor
final class PlinxVideoGravityAdapter {
    var fillsScreen = false {
        didSet { applyGravity() }
    }
    private weak var surfaceLayer: CALayer?
    private weak var videoLayer: CALayer?
    private var surfaceObservation: NSKeyValueObservation?
    private var gravityObservation: NSKeyValueObservation?

    func bind(to layer: CALayer) {
        guard surfaceLayer !== layer else { return }
        unbind()
        surfaceLayer = layer
        surfaceObservation = layer.observe(\.sublayers, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshVideoLayer() }
        }
    }

    func unbind() {
        surfaceObservation = nil
        gravityObservation = nil
        setGravity(.resizeAspect, on: videoLayer)
        videoLayer = nil
        surfaceLayer = nil
    }

    private func refreshVideoLayer() {
        let layer = surfaceLayer?.sublayers?.first {
            $0 is AVPlayerLayer || $0 is AVSampleBufferDisplayLayer
        }
        guard videoLayer !== layer else { applyGravity(); return }
        gravityObservation = nil
        setGravity(.resizeAspect, on: videoLayer)
        videoLayer = layer
        if let native = layer as? AVPlayerLayer {
            gravityObservation = native.observe(\.videoGravity, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.applyGravity() }
            }
        } else if let software = layer as? AVSampleBufferDisplayLayer {
            gravityObservation = software.observe(\.videoGravity, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.applyGravity() }
            }
        }
        applyGravity()
    }

    private func applyGravity() {
        setGravity(fillsScreen ? .resizeAspectFill : .resizeAspect, on: videoLayer)
    }

    private func setGravity(_ gravity: AVLayerVideoGravity, on layer: CALayer?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if let native = layer as? AVPlayerLayer, native.videoGravity != gravity {
            native.videoGravity = gravity
        } else if let software = layer as? AVSampleBufferDisplayLayer, software.videoGravity != gravity {
            software.videoGravity = gravity
        }
    }
}

private struct PlinxVideoGravityBridge: UIViewRepresentable {
    let fillsScreen: Bool

    func makeUIView(context: Context) -> SurfaceProbe { SurfaceProbe() }

    func updateUIView(_ view: SurfaceProbe, context: Context) {
        view.adapter.fillsScreen = fillsScreen
        view.resolveSurface()
    }

    static func dismantleUIView(_ view: SurfaceProbe, coordinator: ()) {
        view.adapter.unbind()
    }

    final class SurfaceProbe: UIView {
        let adapter = PlinxVideoGravityAdapter()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { adapter.unbind(); return }
            // SwiftUI may attach the marker before attaching the video view.
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.resolveSurface()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            resolveSurface()
        }

        func resolveSurface() {
            guard window != nil else { return }
            var ancestor = superview
            while let view = ancestor {
                if let surface = findSurface(in: view) {
                    adapter.bind(to: surface.layer)
                    return
                }
                ancestor = view.superview
            }
        }

        private func findSurface(in view: UIView) -> AetherPlayerView? {
            if let surface = view as? AetherPlayerView { return surface }
            for child in view.subviews {
                if let surface = findSurface(in: child) { return surface }
            }
            return nil
        }
    }
}
#endif
