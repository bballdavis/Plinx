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
        XCTAssertEqual(
            PlinxBrandAsset.stackedOnLight.rawValue,
            "BrandLockupStackedOnLight"
        )
    }

    func test_parentalGateSemantics_useDarkTextAndGreenActionOnBrandGradient() {
        XCTAssertEqual(PlinxBrandingSemantics.parentalGateTitleColorValue, "darkOnBrandGradient")
        XCTAssertEqual(PlinxBrandingSemantics.parentalGateUnlockStyleValue, "greenBrandPrimary")
        XCTAssertEqual(
            PlinxBrandingSemantics.parentalGateTVUnlockStyleValue,
            "darkBrandPrimaryWithGradientBorder"
        )
    }

    func test_heroLoadingSemantic_usesAnimatedMarkAndWordmark() {
        XCTAssertEqual(
            PlinxBrandingSemantics.heroLoadingStyleValue,
            "heroAnimatedBeaconWithWordmark"
        )
    }

    func test_launchHeroAsset_usesTheActiveHeroFootprint() {
        let storyboardURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/LaunchScreen.storyboard")
        let storyboard = try? String(contentsOf: storyboardURL, encoding: .utf8)

        XCTAssertNotNil(storyboard)
        XCTAssertTrue(storyboard?.contains("image=\"LaunchHeroIdentity\"") == true)
        XCTAssertTrue(storyboard?.contains("constant=\"184\"") == true)
        XCTAssertTrue(storyboard?.contains("constant=\"260\"") == true)
    }

    /// Zero collection: Trakt and Simkl sync and upstream error reporting were removed, so the
    /// shipped copy must not describe them (docs/security/privacy-and-safety.md).
    func test_stringCatalog_shipsNoTrackerOrErrorReportCopy() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
        let catalogData = try Data(contentsOf: catalogURL)
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: catalogData) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        XCTAssertFalse(strings.isEmpty)

        let removedKeyPrefixes = ["settings.privacy.", "integrations.trackers."]
        for key in strings.keys where removedKeyPrefixes.contains(where: { key.hasPrefix($0) }) {
            XCTFail("Removed tracker or error-report copy is back in the string catalog: \(key)")
        }
        let catalogText = String(decoding: catalogData, as: UTF8.self).lowercased()
        XCTAssertFalse(catalogText.contains("trakt"))
        XCTAssertFalse(catalogText.contains("simkl"))

        let missing = "plinx.test.missing-localization"
        XCTAssertNotEqual(
            Bundle.main.localizedString(forKey: "settings.server.connection", value: missing, table: nil),
            missing,
            "The app's compiled string table must be readable for the checks below to mean anything"
        )
        for key in [
            "settings.privacy.trackers",
            "settings.privacy.errorReports",
            "settings.privacy.errorReports.footer",
        ] {
            XCTAssertEqual(
                Bundle.main.localizedString(forKey: key, value: missing, table: nil),
                missing,
                "The app bundle still ships \(key)"
            )
        }
    }

    func test_signInPrimaryButtonStyleSemantic_isLiquidGlassPrimary() {
        XCTAssertEqual(PlinxBrandingSemantics.signInPrimaryButtonStyleValue, "liquidGlassPrimary")
    }

    func test_brandHierarchyMetrics_keepSignInAndHomeIdentityProminent() {
        XCTAssertEqual(PlinxBrandLayoutMetrics.signInCompactLogoWidth, 132)
        XCTAssertEqual(PlinxBrandLayoutMetrics.signInExpandedLogoWidth, 176)
        XCTAssertEqual(PlinxBrandLayoutMetrics.signInCompactTitleSize, 40)
        XCTAssertEqual(PlinxBrandLayoutMetrics.signInExpandedTitleSize, 58)

        XCTAssertEqual(
            PlinxBrandLayoutMetrics.homeHeaderLogoHeight(chromeButtonSideLength: 52),
            52
        )
        XCTAssertEqual(
            PlinxBrandLayoutMetrics.homeHeaderLogoWidth(chromeButtonSideLength: 52),
            195
        )
        XCTAssertEqual(
            PlinxBrandLayoutMetrics.homeHeaderLogoHeight(chromeButtonSideLength: 78),
            56
        )
        XCTAssertEqual(PlinxBrandLayoutMetrics.homeHeaderLogoGapReductionFactor, 0.5)
        XCTAssertEqual(
            PlinxBrandLayoutMetrics.homeHeaderLogoGap(logoHeight: 52),
            21.067,
            accuracy: 0.01
        )
    }
}
