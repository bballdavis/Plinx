// ─────────────────────────────────────────────────────────────────────────────
// PlinxUITests.swift — Swift Testing logic tests for PlinxUI components
// ─────────────────────────────────────────────────────────────────────────────
//
// These tests verify component properties and configuration invariants without
// requiring a simulator or UIKit. They run as part of `swift test` on any
// macOS machine.
//
// References: docs/development/ui-testing.md — "Logic" layer
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(Testing)
import Testing
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
@testable import PlinxUI

// MARK: - PlinxTheme

@MainActor
struct PlinxThemeTests {

    @Test func defaultGlassCornerRadiusIsPositive() {
        #expect(PlinxTheme().glass.cornerRadius > 0)
    }

    @Test func defaultGlassOpacitiesAreInRange() {
        let glass = PlinxTheme().glass
        #expect(glass.highlightOpacity >= 0 && glass.highlightOpacity <= 1)
        #expect(glass.shadowOpacity >= 0 && glass.shadowOpacity <= 1)
    }

    @Test func defaultGlassOffsetsCreateDepth() {
        // Highlight and shadow must be offset in opposite-ish directions to
        // create the Liquid Glass depth illusion.
        let glass = PlinxTheme().glass
        let highlightMag = abs(glass.highlightOffset.width) + abs(glass.highlightOffset.height)
        let shadowMag    = abs(glass.shadowOffset.width)    + abs(glass.shadowOffset.height)
        #expect(highlightMag > 0)
        #expect(shadowMag > 0)
    }

    @Test func defaultPaletteUsesCanonicalBrandColors() {
        let palette = PlinxTheme().palette
        #expect(palette.primary == PlinxBrand.lime)
        #expect(palette.secondary == PlinxBrand.teal)
        #expect(palette.background == PlinxBrand.shell)
        #expect(palette.surface == PlinxBrand.surface)
    }

    #if canImport(AppKit)
    @Test func canonicalBrandColorsUseExactSRGBComponents() throws {
        let lime = try #require(NSColor(PlinxBrand.lime).usingColorSpace(.sRGB))
        let teal = try #require(NSColor(PlinxBrand.teal).usingColorSpace(.sRGB))
        let shell = try #require(NSColor(PlinxBrand.shell).usingColorSpace(.sRGB))

        #expect(abs(lime.redComponent - 158.0 / 255.0) < 0.0001)
        #expect(abs(lime.greenComponent - 238.0 / 255.0) < 0.0001)
        #expect(abs(lime.blueComponent - 115.0 / 255.0) < 0.0001)
        #expect(abs(teal.redComponent - 57.0 / 255.0) < 0.0001)
        #expect(abs(teal.greenComponent - 158.0 / 255.0) < 0.0001)
        #expect(abs(teal.blueComponent - 145.0 / 255.0) < 0.0001)
        #expect(abs(shell.redComponent - 11.0 / 255.0) < 0.0001)
        #expect(abs(shell.greenComponent - 18.0 / 255.0) < 0.0001)
        #expect(abs(shell.blueComponent - 14.0 / 255.0) < 0.0001)
    }
    #endif

    @Test func defaultTypographyUsesRoundedSystemDesign() {
        let typography = PlinxTheme().typography
        #expect(typography.display.design == .rounded)
        #expect(typography.title.design == .rounded)
        #expect(typography.body.design == .rounded)
        #expect(typography.button.design == .rounded)
    }

    @Test func ambientBrandTokensStayWithinRestrainedOpacityBudget() {
        #expect(PlinxBrand.Ambient.restrainedLimeOpacity == 0.04)
        #expect(PlinxBrand.Ambient.restrainedTealOpacity == 0.06)
        #expect(PlinxBrand.Ambient.heroLimeOpacity == 0.06)
        #expect(PlinxBrand.Ambient.heroTealOpacity == 0.08)
        #expect(PlinxBrand.Ambient.limeCenter == UnitPoint(x: 0.08, y: 0.02))
        #expect(PlinxBrand.Ambient.tealCenter == UnitPoint(x: 0.94, y: 0.96))
    }
}

// MARK: - PlinxMediaCard

@MainActor
struct PlinxMediaCardTests {

    @Test func defaultAspectRatioIsPortrait() {
        #expect(abs(PlinxMediaCard(title: "Test").aspectRatio - (2.0 / 3.0)) < 0.0001)
    }

    @Test func optionalPropertiesDefaultToNil() {
        let card = PlinxMediaCard(title: "Test")
        #expect(card.subtitle == nil)
        #expect(card.imageURL == nil)
        #expect(card.progress == nil)
    }

    @Test func titleIsPropagated() {
        #expect(PlinxMediaCard(title: "Adventure Time").title == "Adventure Time")
    }

    @Test func subtitleIsPropagated() {
        #expect(PlinxMediaCard(title: "T", subtitle: "Season 1").subtitle == "Season 1")
    }

    @Test func progressIsPropagated() {
        #expect(PlinxMediaCard(title: "T", progress: 0.75).progress == 0.75)
    }

    @Test func landscapeAspectRatioIsAccepted() {
        let card = PlinxMediaCard(title: "T", aspectRatio: 16.0 / 9.0)
        #expect(abs(card.aspectRatio - (16.0 / 9.0)) < 0.0001)
    }
}

// MARK: - PlinxErrorView

@MainActor
struct PlinxErrorViewTests {

    @Test func messageIsPropagated() {
        #expect(PlinxErrorView(message: "Connection failed").message == "Connection failed")
    }

    @Test func retryIsNilByDefault() {
        #expect(PlinxErrorView(message: "Error").onRetry == nil)
    }

    @Test func retryClosureIsPresentWhenProvided() {
        let view = PlinxErrorView(message: "Error") { /* retry */ }
        #expect(view.onRetry != nil)
    }
}

// MARK: - Plinx loading system

@MainActor
struct PlinxLoadingIndicatorTests {

    @Test func defaultsToCompactTransparentIndicator() {
        let indicator = PlinxLoadingIndicator()
        #expect(indicator.size == .compact)
        #expect(indicator.surface == .transparent)
        #expect(indicator.accessibilityIdentifier == "plinx.loading.indicator")
    }

    @Test func supportsCompactRegularAndHeroGeometry() {
        #expect(PlinxLoadingSize.compact.dimension < PlinxLoadingSize.regular.dimension)
        #expect(PlinxLoadingSize.regular.dimension < PlinxLoadingSize.hero.dimension)
        #expect(PlinxLoadingSize.compact.cornerRadius > 0)
        #expect(PlinxLoadingSize.regular.cornerRadius > 0)
        #expect(PlinxLoadingSize.hero.cornerRadius > 0)
    }

    @Test func videoVariantKeepsSelectedPublicConfiguration() {
        let indicator = PlinxLoadingIndicator(
            size: .hero,
            surface: .video,
            label: "Buffering…",
            accessibilityIdentifier: "player.buffering.plinx"
        )
        #expect(indicator.size == .hero)
        #expect(indicator.surface == .video)
        #expect(indicator.accessibilityIdentifier == "player.buffering.plinx")
    }

    @Test func progressStyleCanBeInstalledAtTheAppRoot() {
        _ = PlinxProgressViewStyle()
    }

    @Test func loadingRolesMapToTheirPrescribedBeaconConfigurations() {
        #expect(PlinxLoadingRole.appTransition.indicatorSize == .hero)
        #expect(PlinxLoadingRole.appTransition.indicatorSurface == .glass)
        #expect(PlinxLoadingRole.appTransition.usesFullLockup)
        #expect(PlinxLoadingRole.content.indicatorSize == .regular)
        #expect(PlinxLoadingRole.content.indicatorSurface == .glass)
        #expect(PlinxLoadingRole.inline.indicatorSize == .compact)
        #expect(PlinxLoadingRole.inline.indicatorSurface == .transparent)
        #expect(PlinxLoadingRole.playback.indicatorSize == .playback)
        #expect(PlinxLoadingRole.playback.indicatorSurface == .video)
    }

    @Test func loadingStatePreservesCallerOwnedLocalizationResources() {
        let label = LocalizedStringResource("Please wait")
        let state = PlinxLoadingStateView(role: .content, label: label)
        #expect(state.role == .content)
        #expect(state.label != nil)
    }

    @Test func calmPremiumFocusStyleKeepsSelectionAndFocusPoliciesDistinct() {
        let style = PlinxFocusSurfaceStyle.calmPremium
        #expect(style.selectionOpacity < style.focusRingOpacity)
        #expect(style.focusedScale > 1)
        #expect(style.focusedScale < 1.1)
        #expect(style.focusedShadowRadius > 0)
    }
}
#endif
