import PlinxUI
import PlinxCore
import SwiftUI
#if os(iOS)
import AetherEngine
import AVFoundation
import UIKit
#endif

/// Plinx-styled player screen around the upstream `PlayerWrapper`.
///
/// Plinx adds its branded loading and buffering presentation, the video fill
/// toggle and the More Actions menu (watched state, More Info). Playback is
/// authorized at the load site through `ContentSafetyGate`, so every queue
/// item, autoplay and SharePlay item is checked before it plays.
struct PlinxPlayerView: View {
    @Binding var isPresented: Bool
    let viewModel: PlayerViewModel
    /// The services of the playing item's server; `nil` for a downloaded file, which offers no quick actions.
    let services: MediaServices?
    let onRequestMoreInfo: (MediaItem) -> Void

    @Environment(PlinxWatchStatusStore.self) private var watchStatusStore
    @State private var quickActionMedia: MediaItem?
    @State private var quickActionErrorMessage: String?
    #if os(tvOS)
    /// The item on screen, which autoplay, queue picks and SharePlay move past `viewModel`'s first item.
    @State private var currentMedia: MediaItem?
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlinxPlayerPlaybackView(
                viewModel: viewModel,
                onExit: {
                    isPresented = false
                },
                onCurrentMediaChange: { media in
                    #if os(tvOS)
                    currentMedia = media
                    #endif
                }
            )
            // PlayerSurfaceView extends the video itself to every edge. Keep
            // the wrapper's safe area so controls avoid the Duo status region
            // and the closed display's camera and home indicator.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(iOS)
            // The More Actions button lives in the player header, so it shows
            // and hides with the rest of the auto-hiding controls. The header
            // passes the item on screen, which autoplay may have advanced.
            .environment(\.plinxPlayerMoreActions, moreActionsHandler)
            .allowsHitTesting(quickActionMedia == nil)
            .accessibilityHidden(quickActionMedia != nil)
            #endif
            #if os(tvOS)
            .plinxQuickActionLongPress {
                guard services != nil, let media = currentMedia else { return }
                presentQuickActions(for: media)
            }
            .allowsHitTesting(quickActionMedia == nil)
            .accessibilityHidden(quickActionMedia != nil)
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

    #if os(iOS)
    /// No quick actions without the item's server (a downloaded file).
    private var moreActionsHandler: ((MediaItem) -> Void)? {
        guard services != nil else { return nil }
        return { media in presentQuickActions(for: media) }
    }
    #endif

    /// The services of `media`'s own server, the only ones allowed to act on it.
    private func services(for media: MediaItem) -> MediaServices? {
        guard let services, services.identity == media.identity.server else { return nil }
        return services
    }

    private func presentQuickActions(for media: MediaItem) {
        guard ContentSafetyGate.shared.isAllowed(media), services(for: media) != nil else {
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
                    guard ContentSafetyGate.shared.isAllowed(media) else {
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
        guard let services = services(for: media) else {
            quickActionErrorMessage = String(localized: "media.unavailable.title", table: "Plinx")
            return
        }
        do {
            _ = try await watchStatusStore.toggle(
                media,
                services: services,
                isAllowed: ContentSafetyGate.shared.isAllowed(media)
            )
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

/// Plinx presentation around the upstream player: the branded buffering
/// overlay replaces the upstream spinner. The player loads only what
/// `isPlaybackAuthorized` allows (the shared safety gate by default).
struct PlinxPlayerPlaybackView: View {
    let viewModel: PlayerViewModel
    let onExit: () -> Void
    let isPlaybackAuthorized: @MainActor (MediaItem) -> Bool
    /// tvOS only: the item on screen after each change. The iOS header passes it to its own actions.
    let onCurrentMediaChange: @MainActor (MediaItem?) -> Void

    init(
        viewModel: PlayerViewModel,
        onExit: @escaping () -> Void,
        isPlaybackAuthorized: @escaping @MainActor (MediaItem) -> Bool = { ContentSafetyGate.shared.isAllowed($0) },
        onCurrentMediaChange: @escaping @MainActor (MediaItem?) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onExit = onExit
        self.isPlaybackAuthorized = isPlaybackAuthorized
        self.onCurrentMediaChange = onCurrentMediaChange
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            #if os(tvOS)
            PlayerWrapper(
                viewModel: viewModel,
                onExit: onExit,
                showsBufferingOverlay: false,
                isPlaybackAuthorized: isPlaybackAuthorized,
                onCurrentMediaChange: onCurrentMediaChange
            )
            #else
            // The upstream player dismisses its presentation itself.
            PlayerWrapper(
                viewModel: viewModel,
                showsBufferingOverlay: false,
                isPlaybackAuthorized: isPlaybackAuthorized
            )
            .plinxVideoPresentation()
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

/// What the full-screen player shows: the loading screen while a launch
/// prepares, then the player for what `MainCoordinator` presents.
///
/// This is the final check before anything plays: a queue is shown only when
/// every item is allowed, and a downloaded file only when it is allowed. Live
/// TV is not offered, so a live presentation is closed.
struct PlinxPlaybackPresentationView: View {
    @EnvironmentObject private var mainCoordinator: MainCoordinator
    @EnvironmentObject private var playbackLaunchCoordinator: PlaybackLaunchCoordinator
    @State private var session: PlinxPlayerSession?
    let onRequestMoreInfo: (MediaItem) -> Void

    var body: some View {
        Group {
            if let session {
                PlinxPlayerView(
                    isPresented: playerPresentationBinding,
                    viewModel: session.viewModel,
                    services: session.services,
                    onRequestMoreInfo: onRequestMoreInfo
                )
                .environment(session.services)
                // A new presentation is a new player, never the previous one with new data.
                .id(session.key)
            } else {
                PlinxPlaybackLoadingView {
                    closePlayer()
                }
            }
        }
        .task(id: presentationKey) {
            resolveSession(for: presentationKey)
        }
    }

    private var presentationKey: PlinxPlayerSession.Key {
        if let queue = mainCoordinator.selectedMediaQueue, mainCoordinator.selectedMediaServices != nil {
            return .queue(queue.id)
        }
        #if !os(tvOS)
        if let request = mainCoordinator.selectedLocalPlayback {
            return .local(request.id)
        }
        #endif
        if mainCoordinator.selectedLiveTVContext != nil {
            return .live
        }
        return .idle
    }

    private func resolveSession(for key: PlinxPlayerSession.Key) {
        let gate = ContentSafetyGate.shared
        switch key {
        case .idle:
            // A new launch is preparing: show its loading screen. Otherwise the
            // presentation is closing and keeps the player until it is gone.
            if playbackLaunchCoordinator.pendingLaunch != nil {
                session = nil
            }
        case .queue:
            guard let queue = mainCoordinator.selectedMediaQueue,
                  let services = mainCoordinator.selectedMediaServices,
                  queue.items.indices.contains(queue.currentIndex),
                  queue.items.allSatisfy({ gate.isAllowed($0.media) })
            else {
                refuse()
                return
            }
            session = PlinxPlayerSession(
                key: key,
                viewModel: PlayerViewModel(
                    queue: queue,
                    services: services,
                    shouldResumeFromOffset: mainCoordinator.shouldResumeFromOffset,
                    launchNotice: mainCoordinator.playerNotice
                ),
                services: services
            )
        case .local:
            #if !os(tvOS)
            guard let request = mainCoordinator.selectedLocalPlayback,
                  gate.isAllowed(request.media)
            else {
                refuse()
                return
            }
            session = PlinxPlayerSession(
                key: key,
                viewModel: PlayerViewModel(request: request),
                services: nil
            )
            #else
            refuse()
            #endif
        case .live:
            // Live TV is not part of Plinx: its channels carry no ratings.
            refuse()
        }
    }

    private func refuse() {
        session = nil
        closePlayer()
    }

    private func closePlayer() {
        playbackLaunchCoordinator.cancelPendingLaunch()
        mainCoordinator.resetPlayer()
    }

    private var playerPresentationBinding: Binding<Bool> {
        Binding(
            get: { mainCoordinator.isPresentingPlayer },
            set: { isPresented in
                if !isPresented {
                    closePlayer()
                }
            }
        )
    }
}

/// One presented player: what it plays and the services of the item's server.
struct PlinxPlayerSession {
    enum Key: Hashable {
        case idle
        case queue(UUID)
        case local(UUID)
        case live
    }

    let key: Key
    let viewModel: PlayerViewModel
    let services: MediaServices?
}

#if os(iOS)
private struct PlinxVideoFillKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}

private struct PlinxPlayerMoreActionsKey: EnvironmentKey {
    static let defaultValue: ((MediaItem) -> Void)? = nil
}

extension EnvironmentValues {
    var plinxVideoFill: Binding<Bool>? {
        get { self[PlinxVideoFillKey.self] }
        set { self[PlinxVideoFillKey.self] = newValue }
    }

    /// Opens the player's quick-action menu for the item on screen. `nil`
    /// hides the header button, for example in offline playback.
    var plinxPlayerMoreActions: ((MediaItem) -> Void)? {
        get { self[PlinxPlayerMoreActionsKey.self] }
        set { self[PlinxPlayerMoreActionsKey.self] = newValue }
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
/// Keeping this outside the engine leaves its private layer ownership untouched.
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
