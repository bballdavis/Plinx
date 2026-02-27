import XCTest
@testable import Plinx

final class BrandingAssetsTests: XCTestCase {

    func test_fullColorLogoAssetName_isPinnedForBrandingViews() {
        XCTAssertEqual(PlinxBrandingSemantics.fullColorLogoAssetName, "LogoFullColor")
    }

    func test_parentalGateTitleColorSemantic_isAccentColor() {
        XCTAssertEqual(PlinxBrandingSemantics.parentalGateTitleColorValue, "darkOnGreenGradient")
    }

    func test_signInPrimaryButtonStyleSemantic_isLiquidGlassPrimary() {
        XCTAssertEqual(PlinxBrandingSemantics.signInPrimaryButtonStyleValue, "liquidGlassPrimary")
    }
}
