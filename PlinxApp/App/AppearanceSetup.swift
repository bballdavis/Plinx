import UIKit
import PlinxUI

/// Applies `PlinxTheme` globally via UIKit appearance proxies.
///
/// Called once from `PlinxApp.body` via `.onAppear`. This ensures that any
/// Strimr views that haven't yet been replaced by Plinx equivalents still
/// receive consistent Plinx branding (tint, navigation bar style).
enum AppearanceSetup {
    static func apply(_ theme: PlinxTheme) {
        // Navigation bar — transparent, white text
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.buttonAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(theme.palette.accent)
        ]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(theme.palette.accent)

        // Tab bar — transparent (Plinx uses a custom tab bar, but belt-and-suspenders)
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        UITabBar.appearance().standardAppearance = tabAppearance

        // Global tint
        UIView.appearance(whenContainedInInstancesOf: [UIWindow.self]).tintColor =
            UIColor(theme.palette.accent)
    }
}
