import SwiftUI

/// Platform-neutral sizing policy shared by the iOS and tvOS player chrome.
///
/// The concrete iOS controls live in a file excluded from the tvOS target, so
/// layout decisions used by shared player surfaces must remain in this source.
enum PlinxPlayerControlLayout {
    static let emphasisScale: CGFloat = 1.5
    static let baseHeaderButtonSize: CGFloat = 42
    static let baseHeaderIconSize: CGFloat = 17
    static let baseHeaderCornerRadius: CGFloat = 14
    static let baseTitleSize: CGFloat = 20

    static let headerButtonSize = baseHeaderButtonSize * emphasisScale
    static let headerIconSize = baseHeaderIconSize * emphasisScale
    static let headerCornerRadius = baseHeaderCornerRadius * emphasisScale
    static let titleSize = baseTitleSize * emphasisScale

    static func scale(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> CGFloat {
        switch (horizontalSizeClass, verticalSizeClass) {
        case (.regular, .regular):
            2
        case (.regular, .compact):
            1.65
        case (.compact, .compact):
            1.45
        default:
            1.3
        }
    }

    static func exitButtonSize(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> CGFloat {
        #if os(tvOS)
        112
        #else
        headerButtonSize
        #endif
    }

    static func exitIconSize(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> CGFloat {
        exitButtonSize(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass
        ) * 0.34
    }
}
