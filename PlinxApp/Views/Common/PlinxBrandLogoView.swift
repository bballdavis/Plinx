import SwiftUI

enum PlinxBrandingSemantics {
    static let fullColorLogoAssetName = "LogoFullColor"
    static let parentalGateTitleColorValue = "darkOnGreenGradient"
    static let signInPrimaryButtonStyleValue = "liquidGlassPrimary"
}

struct PlinxBrandLogoView: View {
    let preferredAssetName: String
    let accessibilityIdentifier: String
    let maxWidth: CGFloat

    init(
        preferredAssetName: String = "LogoFullColor",
        accessibilityIdentifier: String = "branding.logo",
        maxWidth: CGFloat = 240
    ) {
        self.preferredAssetName = preferredAssetName
        self.accessibilityIdentifier = accessibilityIdentifier
        self.maxWidth = maxWidth
    }

    var body: some View {
        Image(preferredAssetName)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: maxWidth)
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityValue(preferredAssetName)
    }
}
