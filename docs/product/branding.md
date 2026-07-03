# Branding

## Brand Sources Of Truth

Canonical brand assets live in:

- `assets/branding/` for reference and marketing artwork
- `PlinxApp/Resources/Assets.xcassets/` for in-app packaged assets

Canonical code sources for runtime branding behavior:

- `Packages/PlinxUI/Sources/PlinxUI/LiquidGlass/PlinxTheme.swift`
- `PlinxApp/App/ThemeExtensions.swift`
- `PlinxApp/App/AppearanceSetup.swift`
- `PlinxApp/Views/Common/PlinxBrandLogoView.swift`

Canonical semantic constants:

- `PlinxBrandingSemantics.fullColorLogoAssetName`
- `PlinxBrandingSemantics.parentalGateTitleColorValue`
- `PlinxBrandingSemantics.signInPrimaryButtonStyleValue`

## Branding Rules

- No Strimr branding should leak into the shipped Plinx binary.
- Kid-facing surfaces should use Plinx assets, palette, tone, and motion language.
- Accent color is user-selectable, but it must stay inside the allowed Plinx palette.
- Branding decisions should remain consistent across auth, parental gate, loading, navigation chrome, and home/library surfaces.

## Asset Guidance

- Use `assets/branding/` for reference logos, app-store art, and reusable brand exports.
- Use `Assets.xcassets` for packaged runtime images.
- Keep semantic asset names stable when tests or UI logic depend on them.

## Theme Guidance

`PlinxTheme` defines the visual system for:

- palette
- glass styling
- motion/springs
- typography

`ThemeExtensions` and `AppearanceSetup` bridge that theme into shared SwiftUI and UIKit surfaces. If tint, navigation chrome, or tab chrome changes, update those files and refresh this doc if the policy changed.

## Kid-Facing Tone

- playful, high-clarity, and safe
- large touch targets and readable contrast
- no brand confusion with upstream Strimr visuals
- no external-link affordances in kid-facing screens

## Brand-Sensitive Test Expectations

Run these when branding or theme behavior changes:

- `PlinxApp/UnitTests/BrandingAssetsTests.swift`
- `PlinxApp/UITests/BrandingUITests.swift`
- relevant `Packages/PlinxUI` snapshot tests
- any affected app UI smoke tests
