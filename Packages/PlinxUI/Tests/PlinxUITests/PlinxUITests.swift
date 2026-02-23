// ─────────────────────────────────────────────────────────────────────────────
// PlinxUITests.swift — Swift Testing logic tests for PlinxUI components
// ─────────────────────────────────────────────────────────────────────────────
//
// These tests verify component properties and configuration invariants without
// requiring a simulator or UIKit. They run as part of `swift test` on any
// macOS machine.
//
// References: development/UI_TESTING_STRATEGY.md — "Logic" layer
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(Testing)
import Testing
import SwiftUI
@testable import PlinxUI

// MARK: - PlinxTheme

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
}

// MARK: - PlinxMediaCard

struct PlinxMediaCardTests {

    @Test func defaultAspectRatioIsPortrait() {
        #expect(PlinxMediaCard(title: "Test").aspectRatio == 2.0 / 3.0)
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
        #expect(card.aspectRatio == 16.0 / 9.0)
    }
}

// MARK: - PlinxErrorView

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
#endif
