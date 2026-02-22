import UIKit
import PlinxUI

/// Applies `PlinxTheme` globally via UIKit appearance proxies.
///
/// Called once from `PlinxApp.body` via `.onAppear` and again whenever the
/// user-selected accent color changes.  Pass the resolved UIColor so the
/// dynamic accent (from `@AppStorage`) drives UIKit-level rendering (tab bar
/// tints, navigation bar buttons) rather than the static theme default.
enum AppearanceSetup {
    static func apply(_ theme: PlinxTheme, accentColor: UIColor? = nil) {
        let accent = accentColor ?? UIColor(theme.palette.accent)

        // Navigation bar — transparent, white text
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.buttonAppearance.normal.titleTextAttributes = [
            .foregroundColor: accent
        ]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = accent

        // Tab bar — transparent, selected item in user-chosen accent
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().tintColor = accent
        UITabBar.appearance().unselectedItemTintColor = UIColor.white.withAlphaComponent(0.55)

        // Global tint — only set at window level so SwiftUI .tint() can still override
        // child views. Setting this also forces UIKit-hosted views (tab bar) to update.
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first {
            window.tintColor = accent
        }
    }
}
