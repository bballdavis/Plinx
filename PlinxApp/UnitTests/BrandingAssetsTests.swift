import XCTest
@testable import Plinx

final class BrandingAssetsTests: XCTestCase {

    func test_fullColorLogoAssetName_isPinnedForBrandingViews() {
        XCTAssertEqual(PlinxBrandingSemantics.fullColorLogoAssetName, "BrandLockupOnDark")
    }

    func test_brandAssetNames_areTypedAndStable() {
        XCTAssertEqual(PlinxBrandAsset.markColor.rawValue, "BrandMarkColor")
        XCTAssertEqual(PlinxBrandAsset.markWhite.rawValue, "BrandMarkWhite")
        XCTAssertEqual(PlinxBrandAsset.wordmarkWhite.rawValue, "BrandWordmarkWhite")
        XCTAssertEqual(PlinxBrandAsset.lockupOnLight.rawValue, "BrandLockupOnLight")
        XCTAssertEqual(PlinxBrandAsset.lockupOnDark.rawValue, "BrandLockupOnDark")
        XCTAssertEqual(PlinxBrandAsset.lockupWhite.rawValue, "BrandLockupWhite")
        XCTAssertEqual(
            PlinxBrandAsset.stackedOnGradient.rawValue,
            "BrandLockupStackedOnGradient"
        )
    }

    func test_parentalGateSemantics_useDarkTextAndGreenActionOnBrandGradient() {
        XCTAssertEqual(PlinxBrandingSemantics.parentalGateTitleColorValue, "darkOnBrandGradient")
        XCTAssertEqual(PlinxBrandingSemantics.parentalGateUnlockStyleValue, "greenBrandPrimary")
    }

    func test_heroLoadingSemantic_usesAnimatedMarkAndWordmark() {
        XCTAssertEqual(
            PlinxBrandingSemantics.heroLoadingStyleValue,
            "heroAnimatedBeaconWithWordmark"
        )
    }

    func test_signInPrimaryButtonStyleSemantic_isLiquidGlassPrimary() {
        XCTAssertEqual(PlinxBrandingSemantics.signInPrimaryButtonStyleValue, "liquidGlassPrimary")
    }
}
