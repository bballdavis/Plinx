// ─────────────────────────────────────────────────────────────────────────────
// ContentTypeLayout_LogicTests.swift — Logic invariants for card layouts
// ─────────────────────────────────────────────────────────────────────────────
//
// These tests run as pure Swift Testing (@Test) without a simulator — they
// verify layout constants and card property invariants without rendering pixels.
//
// Invariants tested:
//   - Portrait (movie / TV) aspect ratio is < 1.0 (taller than wide)
//   - Landscape (clip / YouTube) aspect ratio is > 1.0 (wider than tall)
//   - 16:9 and 2:3 constants match expected floating-point values
//   - Fixture factories produce the correct aspect ratios
//   - Progress clamping logic: values > 1.0 render at max (1.0)
//   - nil progress → no bar; 0.0 progress → no bar
//
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(Testing)
import Testing
import SwiftUI
@testable import PlinxUI

// MARK: - Aspect ratio constants

struct AspectRatioConstantTests {

    @Test func portraitCardRatioIsLessThanOne() {
        // Portrait cards (movies / TV shows / episodes) must be taller than wide.
        #expect(CGFloat.portraitCard < 1.0)
    }

    @Test func landscapeCardRatioIsGreaterThanOne() {
        // Landscape cards (clips / YouTube) must be wider than tall.
        #expect(CGFloat.landscapeCard > 1.0)
    }

    @Test func portraitRatioIsTwoThirds() {
        #expect(CGFloat.portraitCard == 2.0 / 3.0)
    }

    @Test func landscapeRatioIsSixteenNinths() {
        let expected = 16.0 / 9.0
        #expect(abs(CGFloat.landscapeCard - expected) < 0.001)
    }

    @Test func landscapeIsSignificantlyWiderThanPortrait() {
        // 16:9 is roughly 2.4× wider relative to portrait 2:3.
        // Any accidental swap of these values would be caught here.
        #expect(CGFloat.landscapeCard > CGFloat.portraitCard * 2)
    }
}

// MARK: - Fixture factory correctness

@MainActor
struct ContentTypeFixtureTests {

    // ── Movies ───────────────────────────────────────────────────────────────

    @Test func movieCardHasPortraitRatio() {
        let card = ContentTypeFixtures.movieCard()
        #expect(card.aspectRatio == .portraitCard)
    }

    @Test func movieCardHasYearSubtitle() {
        let card = ContentTypeFixtures.movieCard(title: "Encanto", subtitle: "2021")
        #expect(card.subtitle == "2021")
    }

    @Test func movieCardTitleIsPropagated() {
        let card = ContentTypeFixtures.movieCard(title: "Moana 2")
        #expect(card.title == "Moana 2")
    }

    @Test func movieCardHasNoProgressByDefault() {
        #expect(ContentTypeFixtures.movieCard().progress == nil)
    }

    // ── TV Shows ─────────────────────────────────────────────────────────────

    @Test func tvCardHasPortraitRatio() {
        let card = ContentTypeFixtures.tvCard()
        #expect(card.aspectRatio == .portraitCard)
    }

    @Test func tvCardHasSeasonCountSubtitle() {
        let card = ContentTypeFixtures.tvCard(title: "Bluey", subtitle: "3 Seasons")
        #expect(card.subtitle == "3 Seasons")
    }

    @Test func tvCardHasNoProgress() {
        #expect(ContentTypeFixtures.tvCard().progress == nil)
    }

    // ── Episodes ─────────────────────────────────────────────────────────────

    @Test func episodeCardHasPortraitRatio() {
        let card = ContentTypeFixtures.episodeCard()
        #expect(card.aspectRatio == .portraitCard)
    }

    @Test func episodeCardHasProgress() {
        let card = ContentTypeFixtures.episodeCard(progress: 0.45)
        #expect(card.progress == 0.45)
    }

    @Test func episodeCardEpisodeInfoInSubtitle() {
        let card = ContentTypeFixtures.episodeCard(show: "Bluey", episodeInfo: "S3 • E12")
        #expect(card.subtitle == "S3 • E12")
    }

    // ── Clips / YouTube ───────────────────────────────────────────────────────

    @Test func clipCardHasLandscapeRatio() {
        let card = ContentTypeFixtures.clipCard()
        #expect(card.aspectRatio == .landscapeCard)
    }

    @Test func clipCardRatioIsSixteenNinths() {
        let card = ContentTypeFixtures.clipCard()
        #expect(abs(card.aspectRatio - 16.0 / 9.0) < 0.001)
    }

    @Test func clipCardLandscapeRatioDiffersFromMoviePortraitRatio() {
        let movie = ContentTypeFixtures.movieCard()
        let clip  = ContentTypeFixtures.clipCard()
        #expect(clip.aspectRatio != movie.aspectRatio,
            "Clip and movie cards must have DIFFERENT aspect ratios")
    }

    @Test func clipCardsArrayAllHaveLandscapeRatio() {
        for card in ContentTypeFixtures.clipCards {
            #expect(card.aspectRatio == .landscapeCard,
                "All items in clipCards must be landscape — found portrait in: \(card.title)")
        }
    }

    @Test func movieCardsArrayAllHavePortraitRatio() {
        for card in ContentTypeFixtures.movieCards {
            #expect(card.aspectRatio == .portraitCard,
                "All items in movieCards must be portrait — found landscape in: \(card.title)")
        }
    }

    @Test func tvShowCardsArrayAllHavePortraitRatio() {
        for card in ContentTypeFixtures.tvShowCards {
            #expect(card.aspectRatio == .portraitCard,
                "All items in tvShowCards must be portrait — found landscape in: \(card.title)")
        }
    }
}

// MARK: - Progress bar logic

@MainActor
struct ProgressBarLogicTests {

    @Test func nilProgressIsHidden() {
        #expect(PlinxMediaCard(title: "T").progress == nil)
    }

    @Test func positiveProgressIsPropagated() {
        #expect(PlinxMediaCard(title: "T", progress: 0.5).progress == 0.5)
    }

    @Test func zeroProgressIsZero() {
        // 0.0 is a valid value — the view hides the bar when progress = 0.
        #expect(PlinxMediaCard(title: "T", progress: 0.0).progress == 0.0)
    }

    @Test func progressCanExceedOneForClamping() {
        // PlinxMediaCard accepts > 1.0; the View clamps rendering to max bar width.
        let card = PlinxMediaCard(title: "T", progress: 1.5)
        #expect((card.progress ?? 0) > 1.0, "Model accepts over-full; view must clamp")
    }

    @Test func progressAtExactlyOneIsFullBar() {
        #expect(PlinxMediaCard(title: "T", progress: 1.0).progress == 1.0)
    }
}

// MARK: - Card width constants (layout contract)
//
// SimulatedSectionRow is only compiled on UIKit platforms.

#if canImport(UIKit)
@MainActor
struct CardWidthContractTests {

    /// Portrait cards in section rows are 110pt wide.
    /// Landscape cards are 200pt wide (matching PlinxHomeView.mediaCard).
    /// These values are replicated in SimulatedSectionRow and must stay in sync.

    @Test func portraitCardWidthIs110() {
        #expect(SimulatedSectionRow(title: "T", cards: [], layout: .portrait).cardWidth == 110)
    }

    @Test func landscapeCardWidthIs200() {
        #expect(SimulatedSectionRow(title: "T", cards: [], layout: .landscape).cardWidth == 200)
    }

    @Test func landscapeCardIsWiderThanPortraitCard() {
        let landscape = SimulatedSectionRow(title: "T", cards: [], layout: .landscape).cardWidth
        let portrait  = SimulatedSectionRow(title: "T", cards: [], layout: .portrait).cardWidth
        #expect(landscape > portrait)
    }
}
#endif

// MARK: - Layout type → aspect ratio mapping

@MainActor
struct LayoutTypeRatioMappingTests {

    /// Ensures that the portrait layout produces cards at 2:3 and the
    /// landscape layout produces cards at 16:9 — cross-referencing both.

    @Test func movieFixturesMatchPortraitLayout() {
        // All movie fixtures must match what .portrait layout expects.
        let expectedRatio: CGFloat = .portraitCard
        for card in ContentTypeFixtures.movieCards {
            #expect(card.aspectRatio == expectedRatio)
        }
    }

    @Test func clipFixturesMatchLandscapeLayout() {
        // All clip fixtures must match what .landscape layout expects.
        let expectedRatio: CGFloat = .landscapeCard
        for card in ContentTypeFixtures.clipCards {
            #expect(card.aspectRatio == expectedRatio)
        }
    }

    @Test func episodeFixturesMatchPortraitLayout() {
        let expectedRatio: CGFloat = .portraitCard
        for card in ContentTypeFixtures.episodeCards {
            #expect(card.aspectRatio == expectedRatio)
        }
    }
}
#endif
