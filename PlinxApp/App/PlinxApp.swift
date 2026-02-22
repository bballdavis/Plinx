import SwiftUI
import PlinxCore
import PlinxUI

#if canImport(UIKit)
import UIKit
#endif

@main
struct PlinxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate

    @State private var plexApiContext: PlexAPIContext
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var libraryStore: LibraryStore
    @State private var mainCoordinator: MainCoordinator

    // Plinx-specific state
    @StateObject private var playbackCoordinator = PlaybackCoordinator()
    @State private var safetyPolicy = SafetyPolicy.ratingOnly()
    @State private var theme = PlinxTheme()
    @AppStorage("plinx.babyLockEnabled") private var babyLockEnabled = false

    init() {
        let context = PlexAPIContext()
        let store = LibraryStore(context: context)
        let settings = SettingsManager()
        _plexApiContext = State(initialValue: context)
        _sessionManager = State(initialValue: SessionManager(context: context, libraryStore: store))
        _settingsManager = State(initialValue: settings)
        _libraryStore = State(initialValue: store)
        _mainCoordinator = State(initialValue: MainCoordinator())
    }

    var body: some Scene {
        WindowGroup {
            PlinxContentView()
                .environment(plexApiContext)
                .environment(sessionManager)
                .environment(settingsManager)
                .environment(libraryStore)
                .environment(mainCoordinator)
                .environment(\.plinxTheme, theme)
                .environment(\.safetyPolicy, safetyPolicy)
                .environmentObject(playbackCoordinator)
                .preferredColorScheme(.dark)
                .onAppear { AppearanceSetup.apply(theme) }
                .lifecycleHardening(
                    coordinator: playbackCoordinator,
                    mainCoordinator: mainCoordinator
                )
                .babyLock(isEnabled: $babyLockEnabled)
        }
    }
}
