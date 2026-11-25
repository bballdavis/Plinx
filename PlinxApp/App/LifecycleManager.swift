import SwiftUI
#if !os(tvOS)
import UIKit
#endif
import PlinxCore

/// Applies lifecycle hardening to the Plinx app:
/// - Stops playback and tears down the player engine when the app backgrounds.
/// - Automatically re-presents the player and resumes playback on foreground return.
/// - Stops playback on low-memory warnings.
/// - Stops playback when the screen is captured.
///
/// Only reacts to `.background`, **not** `.inactive`.  `.inactive` fires for
/// transient interruptions (Control Center, notification banners, Slide Over)
/// which should not destroy the player.
///
/// Downloads manage their own network monitoring and task restoration inside
/// `DownloadManager`; this modifier only owns playback.
///
/// Apply once at the root via `.lifecycleHardening(...)`.
struct LifecycleHardeningModifier: ViewModifier {
    /// What was on screen when the app backgrounded, so the player can come
    /// back with fresh metadata and the last reported offset.
    private enum SuspendedPlayback {
        case remote(queue: PlaybackQueue, services: MediaServices)
        #if !os(tvOS)
        case local(LocalPlaybackRequest)
        #endif
    }

    let coordinator: PlaybackCoordinator
    let mainCoordinator: MainCoordinator

    @Environment(\.scenePhase) private var scenePhase

    @State private var suspendedPlayback: SuspendedPlayback?

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) {
                let newPhase = scenePhase
                if newPhase == .background {
                    coordinator.handleBackgrounding()

                    // Stash the active playback before tearing down so the
                    // player can be restored on return to the foreground.
                    suspendedPlayback = currentPlayback()

                    // resetPlayer() clears the presented queue and services,
                    // which dismisses the player and lets PlayerView's
                    // onDisappear destroy the engine.
                    mainCoordinator.resetPlayer()
                } else if newPhase == .active {
                    // Re-present the player if there was an active session
                    // before backgrounding. The new player view loads fresh
                    // metadata (including the last-reported view offset) and
                    // resumes, so playback continues seamlessly.
                    if let playback = suspendedPlayback {
                        suspendedPlayback = nil
                        resume(playback)
                    }
                }
            }
        #if !os(tvOS)
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didReceiveMemoryWarningNotification
                )
            ) { _ in
                coordinator.handleMemoryWarning()
                mainCoordinator.resetPlayer()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIScreen.capturedDidChangeNotification
                )
            ) { _ in
                coordinator.handleBackgrounding()
                mainCoordinator.resetPlayer()
            }
        #endif
    }

    private func currentPlayback() -> SuspendedPlayback? {
        if let queue = mainCoordinator.selectedMediaQueue,
           let services = mainCoordinator.selectedMediaServices
        {
            return .remote(queue: queue, services: services)
        }
        #if !os(tvOS)
        if let request = mainCoordinator.selectedLocalPlayback {
            return .local(request)
        }
        #endif
        return nil
    }

    private func resume(_ playback: SuspendedPlayback) {
        switch playback {
        case let .remote(queue, services):
            mainCoordinator.showPlayer(
                for: queue,
                services: services,
                shouldResumeFromOffset: true,
                notice: nil
            )
        #if !os(tvOS)
        case let .local(request):
            mainCoordinator.showLocalPlayer(request)
        #endif
        }
    }
}

extension View {
    func lifecycleHardening(
        coordinator: PlaybackCoordinator,
        mainCoordinator: MainCoordinator
    ) -> some View {
        modifier(LifecycleHardeningModifier(
            coordinator: coordinator,
            mainCoordinator: mainCoordinator
        ))
    }
}
