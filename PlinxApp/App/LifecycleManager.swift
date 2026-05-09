import SwiftUI
#if !os(tvOS)
import UIKit
#endif
import PlinxCore

/// Applies lifecycle hardening to the Plinx app:
/// - Stops playback and tears down the player engine when the app backgrounds.
/// - Automatically re-presents the player and resumes playback on foreground return.
/// - Stops playback on low-memory warnings.
/// - Stops playback when the screen is locked / captured.
///
/// Only reacts to `.background`, **not** `.inactive`.  `.inactive` fires for
/// transient interruptions (Control Center, notification banners, Slide Over)
/// which should not destroy the player.
///
/// Apply once at the root via `.modifier(LifecycleHardeningModifier(...))`.
struct LifecycleHardeningModifier: ViewModifier {
    let coordinator: PlaybackCoordinator
    let mainCoordinator: MainCoordinator
    #if !os(tvOS)
    let downloadManager: DownloadManager
    #endif

    @Environment(\.scenePhase) private var scenePhase

    /// Stashed play queue so we can re-present the player on foreground return.
    @State private var suspendedPlayQueue: PlayQueueState?

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    coordinator.handleBackgrounding()

                    // Stash the active play queue before tearing down so we can
                    // restore the player when the app comes back to the foreground.
                    suspendedPlayQueue = mainCoordinator.selectedPlayQueue

                    // resetPlayer() nils selectedPlayQueue, which is the actual
                    // source of truth for the fullScreenCover(item:) binding.
                    // This ensures the player sheet fully dismisses and triggers
                    // PlayerView.onDisappear → playerCoordinator.destruct().
                    mainCoordinator.resetPlayer()

                    #if !os(tvOS)
                    downloadManager.stopNetworkMonitoring()
                    #endif
                } else if newPhase == .active {
                    #if !os(tvOS)
                    downloadManager.startNetworkMonitoring()
                    #endif

                    // Re-present the player if there was an active session before
                    // backgrounding.  The new PlayerView will load fresh metadata
                    // (including the last-reported viewOffset) and auto-start
                    // playback, so the user sees their video resume seamlessly.
                    if let playQueue = suspendedPlayQueue {
                        suspendedPlayQueue = nil
                        mainCoordinator.showPlayer(
                            for: playQueue,
                            shouldResumeFromOffset: true
                        )
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
}

extension View {
    #if !os(tvOS)
    func lifecycleHardening(
        coordinator: PlaybackCoordinator,
        mainCoordinator: MainCoordinator,
        downloadManager: DownloadManager
    ) -> some View {
        modifier(LifecycleHardeningModifier(
            coordinator: coordinator,
            mainCoordinator: mainCoordinator,
            downloadManager: downloadManager
        ))
    }
    #else
    func lifecycleHardening(
        coordinator: PlaybackCoordinator,
        mainCoordinator: MainCoordinator
    ) -> some View {
        modifier(LifecycleHardeningModifier(
            coordinator: coordinator,
            mainCoordinator: mainCoordinator
        ))
    }
    #endif
}
