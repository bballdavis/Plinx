import SwiftUI
import UIKit
import PlinxCore

/// Applies lifecycle hardening to the Plinx app:
/// - Stops playback and clears sensitive state when the app backgrounds.
/// - Stops playback on low-memory warnings.
/// - Stops playback when the screen is locked / captured.
///
/// Apply once at the root via `.modifier(LifecycleHardeningModifier(...))`.
struct LifecycleHardeningModifier: ViewModifier {
    let coordinator: PlaybackCoordinator
    let mainCoordinator: MainCoordinator

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background || newPhase == .inactive {
                    coordinator.handleBackgrounding()
                    // Dismissing the player sheet triggers PlayerView.onDisappear
                    // → playerCoordinator.destruct() → MPVKit teardown.
                    mainCoordinator.isPresentingPlayer = false
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didReceiveMemoryWarningNotification
                )
            ) { _ in
                coordinator.handleMemoryWarning()
                mainCoordinator.isPresentingPlayer = false
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIScreen.capturedDidChangeNotification
                )
            ) { _ in
                // Also fires on screen lock via AirPlay to unsecured display.
                coordinator.handleBackgrounding()
                mainCoordinator.isPresentingPlayer = false
            }
    }
}

extension View {
    func lifecycleHardening(coordinator: PlaybackCoordinator, mainCoordinator: MainCoordinator) -> some View {
        modifier(LifecycleHardeningModifier(coordinator: coordinator, mainCoordinator: mainCoordinator))
    }
}
