import SwiftUI
import PlinxUI

enum PlinxBrandAsset: String, CaseIterable {
    case markColor = "BrandMarkColor"
    case markWhite = "BrandMarkWhite"
    case markCharcoal = "BrandMarkCharcoal"
    case wordmarkWhite = "BrandWordmarkWhite"
    case lockupOnLight = "BrandLockupOnLight"
    case lockupOnDark = "BrandLockupOnDark"
    case lockupWhite = "BrandLockupWhite"
    case stackedOnGradient = "BrandLockupStackedOnGradient"
    case stackedOnLight = "BrandLockupStackedOnLight"

    var sourceAssetName: String {
        switch self {
        case .stackedOnLight:
            // The on-light variant deliberately reuses the canonical stacked
            // vector as a template so its geometry cannot drift from the
            // white treatment.
            PlinxBrandAsset.stackedOnGradient.rawValue
        default:
            rawValue
        }
    }

    var usesTemplateRendering: Bool {
        self == .stackedOnLight
    }
}

enum PlinxBrandingSemantics {
    static let fullColorLogoAssetName = PlinxBrandAsset.lockupOnDark.rawValue
    static let parentalGateTitleColorValue = "darkOnBrandGradient"
    static let parentalGateUnlockStyleValue = "greenBrandPrimary"
    static let parentalGateTVUnlockStyleValue = "darkBrandPrimaryWithGradientBorder"
    static let heroLoadingStyleValue = "heroAnimatedBeaconWithWordmark"
    static let signInPrimaryButtonStyleValue = "liquidGlassPrimary"
}

enum PlinxBrandLayoutMetrics {
    static let signInCompactLogoWidth: CGFloat = 320
    static let signInExpandedLogoWidth: CGFloat = 380
    static let signInCompactTitleSize: CGFloat = 34
    static let signInExpandedTitleSize: CGFloat = 44
    static let homeHeaderLogoGapReductionFactor: CGFloat = 0.5

    private static let homeHeaderMarkX: CGFloat = 47.40579710144927
    private static let homeHeaderMarkScale: CGFloat = 0.2898550724637681
    private static let homeHeaderMarkWidth: CGFloat = 839 * homeHeaderMarkScale
    static let homeHeaderMarkHeight: CGFloat = 897 * homeHeaderMarkScale
    private static let homeHeaderWordmarkX: CGFloat = 501.2623574144487
    private static let homeHeaderWordmarkScale: CGFloat = 0.3193916349809886
    private static let homeHeaderWordmarkWidth: CGFloat = 1520 * homeHeaderWordmarkScale
    private static let homeHeaderWordmarkHeight: CGFloat = 526 * homeHeaderWordmarkScale

    static func homeHeaderLogoGap(logoHeight: CGFloat) -> CGFloat {
        let originalGap = homeHeaderWordmarkX - homeHeaderMarkX - homeHeaderMarkWidth
        return originalGap
            * homeHeaderLogoGapReductionFactor
            * logoHeight
            / homeHeaderMarkHeight
    }

    static func homeHeaderMarkSize(logoHeight: CGFloat) -> CGSize {
        // Scale by the visible mark bounds rather than the source canvas so
        // the lockup actually fills the same row as its chrome controls.
        let scale = logoHeight / homeHeaderMarkHeight
        return CGSize(
            width: homeHeaderMarkWidth * scale,
            height: homeHeaderMarkHeight * scale
        )
    }

    static func homeHeaderWordmarkSize(logoHeight: CGFloat) -> CGSize {
        let scale = logoHeight / homeHeaderMarkHeight
        return CGSize(
            width: homeHeaderWordmarkWidth * scale,
            height: homeHeaderWordmarkHeight * scale
        )
    }

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
        Image(asset.sourceAssetName)
            .renderingMode(asset.usesTemplateRendering ? .template : .original)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: maxWidth)
            .foregroundStyle(asset.usesTemplateRendering ? PlinxBrand.shell : Color.primary)
            .accessibilityLabel("Plinx")
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityValue(asset.rawValue)
    }
}

struct PlinxHomeHeaderLogoView: View {
    let accessibilityIdentifier: String
    let maxWidth: CGFloat
    let logoHeight: CGFloat

    init(
        accessibilityIdentifier: String = "home.header.logo",
        maxWidth: CGFloat,
        logoHeight: CGFloat
    ) {
        self.accessibilityIdentifier = accessibilityIdentifier
        self.maxWidth = maxWidth
        self.logoHeight = logoHeight
    }

    var body: some View {
        HStack(
            alignment: .center,
            spacing: PlinxBrandLayoutMetrics.homeHeaderLogoGap(logoHeight: logoHeight)
        ) {
            let markSize = PlinxBrandLayoutMetrics.homeHeaderMarkSize(logoHeight: logoHeight)
            Image(PlinxBrandAsset.markColor.rawValue)
                .resizable()
                .scaledToFit()
                .frame(width: markSize.width, height: markSize.height)

            let wordmarkSize = PlinxBrandLayoutMetrics.homeHeaderWordmarkSize(logoHeight: logoHeight)
            Image(PlinxBrandAsset.wordmarkWhite.rawValue)
                .resizable()
                .scaledToFit()
                .frame(width: wordmarkSize.width, height: wordmarkSize.height)
        }
        .padding(.leading, logoHeight * 47.40579710144927 / PlinxBrandLayoutMetrics.homeHeaderMarkHeight)
        .frame(
            width: min(
                maxWidth,
                PlinxBrandLayoutMetrics.homeHeaderLogoWidth(
                    chromeButtonSideLength: logoHeight
                )
            ),
            height: logoHeight,
            alignment: .leading
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Plinx")
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityValue(PlinxBrandAsset.lockupOnDark.rawValue)
        .accessibilityAddTraits(.isImage)
    }
}
