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
    #if canImport(UIKit)
    private let memoryWarningPublisher = NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
    #endif

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
        #if canImport(UIKit)
        .onReceive(memoryWarningPublisher) { _ in
            playbackCoordinator.handleMemoryWarning()
        }
        #endif
    }
}
