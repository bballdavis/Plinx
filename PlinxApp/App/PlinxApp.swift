import SwiftUI
import PlinxCore
import PlinxUI

@main
struct PlinxApp: App {
    @StateObject private var playbackCoordinator = PlaybackCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(playbackCoordinator)
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase != .active {
                playbackCoordinator.handleBackgrounding()
            }
        }
    }
}
