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

enum PlinxBrandLayoutMetrics {
    static let signInCompactLogoWidth: CGFloat = 280
    static let signInExpandedLogoWidth: CGFloat = 380
    static let signInCompactTitleSize: CGFloat = 34
    static let signInExpandedTitleSize: CGFloat = 44

    static func homeHeaderLogoHeight(chromeButtonSideLength: CGFloat) -> CGFloat {
        min(chromeButtonSideLength, 56)
    }

    static func homeHeaderLogoWidth(chromeButtonSideLength: CGFloat) -> CGFloat {
        homeHeaderLogoHeight(chromeButtonSideLength: chromeButtonSideLength) * 3.75
    }
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
