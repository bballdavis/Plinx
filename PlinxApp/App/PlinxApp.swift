import SwiftUI
import PlinxCore
import PlinxUI

#if canImport(UIKit)
import UIKit
#endif

@main
struct PlinxApp: App {
    @StateObject private var playbackCoordinator = PlaybackCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(playbackCoordinator)
                #if canImport(UIKit)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    playbackCoordinator.handleMemoryWarning()
                }
                #endif
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase != .active {
                playbackCoordinator.handleBackgrounding()
            }
        }
    }
}
