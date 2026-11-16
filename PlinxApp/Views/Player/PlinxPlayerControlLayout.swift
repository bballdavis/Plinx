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
    static let compactTitleSize: CGFloat = 17

    struct ChromeInsets: Equatable {
        let horizontal: CGFloat
        let vertical: CGFloat
        let bottomSpacing: CGFloat
    }

    /// The hidden Duo status sidebar can leave a large, one-sided lateral
    /// inset during playback. Reclaim it in landscape while retaining normal
    /// camera/notch insets and all vertical safe areas.
    static func reclaimedStatusInsets(size: CGSize, safeArea: EdgeInsets) -> EdgeInsets {
        guard size.width > size.height,
              max(safeArea.leading, safeArea.trailing) >= 80,
              min(safeArea.leading, safeArea.trailing) < 20
        else { return EdgeInsets() }
        return EdgeInsets(top: 0, leading: safeArea.leading, bottom: 0, trailing: safeArea.trailing)
    }

    /// Uses the live safe container, so opening, closing, and rotating a Duo
    /// updates the chrome without identifying a particular device model.
    static func chromeInsets(width: CGFloat, height: CGFloat) -> ChromeInsets {
        ChromeInsets(
            horizontal: width >= 700 ? 28 : 16,
            vertical: height < 450 ? 8 : 16,
            bottomSpacing: height < 450 ? 10 : 18
        )
    }

    static func headerPresentation(width: CGFloat, height: CGFloat) -> HeaderPresentation {
        if height > width {
            return width < 600 ? .compactPortrait : .spaciousPortrait
        }
        return .landscape
    }

    static func titleMaxWidth(width: CGFloat, presentation: HeaderPresentation) -> CGFloat {
        switch presentation {
        case .compactPortrait:
            max(0, width - 40)
        case .landscape:
            min(max(0, width - 260), 720)
        case .spaciousPortrait:
            min(max(0, width - 220), 720)
        }
    }

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
        horizontalSizeClass _: UserInterfaceSizeClass?,
        verticalSizeClass _: UserInterfaceSizeClass?
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

enum HeaderPresentation: Equatable {
    case compactPortrait
    case landscape
    case spaciousPortrait
}
