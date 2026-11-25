import SwiftUI
#if !os(tvOS)
import UIKit
#endif
import PlinxCore

/// Decides whether leaving the foreground closes the player.
///
/// Closing is the default, so nothing plays outside the app unless a parent
/// allows it. On iPhone and iPad a parent can turn on Picture in Picture or
/// background audio in protected settings; the player then stays open and
/// `PlayerView` decides on its own, as upstream does: it keeps playing in a
/// Picture in Picture window or as background audio, and pauses otherwise.
/// tvOS offers neither setting, so its player always closes.
enum PlayerBackgroundPolicy {
    static func closesPlayerOnBackground(_ playback: PlaybackSettings) -> Bool {
        #if os(tvOS)
        return true
        #else
        return !(playback.pictureInPicture || playback.backgroundAudio)
        #endif
    }
}

/// Applies lifecycle hardening to the Plinx app:
/// - Stops playback and tears down the player engine when the app backgrounds,
///   unless a parent allowed playback outside the app (`PlayerBackgroundPolicy`).
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
    /// The settings the player reads; the App Review sample library has its own.
    let settingsManager: SettingsManager

    @Environment(\.scenePhase) private var scenePhase

    @State private var suspendedPlayback: SuspendedPlayback?

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) {
                let newPhase = scenePhase
                if newPhase == .background {
                    guard PlayerBackgroundPolicy.closesPlayerOnBackground(settingsManager.playback) else {
                        // A parent allowed Picture in Picture or background
                        // audio. Closing the player here would end both, so it
                        // stays open and pauses itself unless one of them
                        // keeps it playing.
                        suspendedPlayback = nil
                        return
                    }

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
        mainCoordinator: MainCoordinator,
        settingsManager: SettingsManager
    ) -> some View {
        modifier(LifecycleHardeningModifier(
            coordinator: coordinator,
            mainCoordinator: mainCoordinator,
            settingsManager: settingsManager
        ))
    }
}
