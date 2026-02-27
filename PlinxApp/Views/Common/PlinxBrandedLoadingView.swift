import SwiftUI
import PlinxUI

/// The green gradient matching the Icon Composer `icon.json` fill used across
/// all full-screen branded surfaces (splash, parental gate, etc.).
extension LinearGradient {
    static var plinxBrandGreen: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.619, green: 0.933, blue: 0.450),
                Color(red: 0.225, green: 0.620, blue: 0.570)
            ],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.7)
        )
    }
}

struct PlinxBrandedLoadingView: View {
    @Environment(\.plinxTheme) private var theme

    var titleKey: LocalizedStringKey?
    var preferredLogoAssetName: String
    var logoAccessibilityIdentifier: String
    var showsProgressView: Bool
    /// When true the view fills the screen with the brand green gradient
    /// background. Use for full-screen splash/loading contexts.
    var fillsBackground: Bool

    init(
        titleKey: LocalizedStringKey? = nil,
        preferredLogoAssetName: String = "LogoFullColor",
        logoAccessibilityIdentifier: String = "branding.logo",
        showsProgressView: Bool = true,
        fillsBackground: Bool = false
    ) {
        self.titleKey = titleKey
        self.preferredLogoAssetName = preferredLogoAssetName
        self.logoAccessibilityIdentifier = logoAccessibilityIdentifier
        self.showsProgressView = showsProgressView
        self.fillsBackground = fillsBackground
    }

    var body: some View {
        VStack(spacing: 18) {
            PlinxBrandLogoView(
                preferredAssetName: preferredLogoAssetName,
                accessibilityIdentifier: logoAccessibilityIdentifier,
                maxWidth: 240
            )

            if showsProgressView {
                ProgressView()
                    .controlSize(.regular)
                    .tint(theme.palette.primary)
            }

            if let titleKey {
                Text(titleKey)
                    .font(.subheadline)
                    .foregroundStyle(fillsBackground ? Color(red: 0.1, green: 0.2, blue: 0.15) : .secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: fillsBackground ? .infinity : nil,
               maxHeight: fillsBackground ? .infinity : nil)
        .background {
            if fillsBackground {
                LinearGradient.plinxBrandGreen.ignoresSafeArea()
            }
        }
    }
}
