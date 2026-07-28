import SwiftUI

enum PlinxBrandAsset: String, CaseIterable {
    case markColor = "BrandMarkColor"
    case markWhite = "BrandMarkWhite"
    case markCharcoal = "BrandMarkCharcoal"
    case wordmarkWhite = "BrandWordmarkWhite"
    case lockupOnLight = "BrandLockupOnLight"
    case lockupOnDark = "BrandLockupOnDark"
    case lockupWhite = "BrandLockupWhite"
    case stackedOnGradient = "BrandLockupStackedOnGradient"
}

enum PlinxBrandingSemantics {
    static let fullColorLogoAssetName = PlinxBrandAsset.lockupOnDark.rawValue
    static let parentalGateTitleColorValue = "darkOnBrandGradient"
    static let parentalGateUnlockStyleValue = "greenBrandPrimary"
    static let heroLoadingStyleValue = "heroAnimatedBeaconWithWordmark"
    static let signInPrimaryButtonStyleValue = "liquidGlassPrimary"
}

struct PlinxBrandLogoView: View {
    let asset: PlinxBrandAsset
    let accessibilityIdentifier: String
    let maxWidth: CGFloat

    init(
        asset: PlinxBrandAsset = .lockupOnDark,
        accessibilityIdentifier: String = "branding.logo",
        maxWidth: CGFloat = 240
    ) {
        self.asset = asset
        self.accessibilityIdentifier = accessibilityIdentifier
        self.maxWidth = maxWidth
    }

    var body: some View {
        Image(asset.rawValue)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: maxWidth)
            .accessibilityLabel("Plinx")
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityValue(asset.rawValue)
    }
}
