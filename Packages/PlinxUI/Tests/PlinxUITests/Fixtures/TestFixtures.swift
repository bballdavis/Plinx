// ─────────────────────────────────────────────────────────────────────────────
// TestFixtures.swift — Realistic simulation data for PlinxUI component tests
// ─────────────────────────────────────────────────────────────────────────────
//
// Factories for PlinxMediaCard instances that mirror real Plex content types:
//
//   ContentTypeFixtures.movieCards    → portrait 2:3, title + year
//   ContentTypeFixtures.tvShowCards   → portrait 2:3, title + season count
//   ContentTypeFixtures.episodeCards  → portrait 2:3, episode info + progress
//   ContentTypeFixtures.clipCards     → LANDSCAPE 16:9, title + source
//
// Image URLs are nil — tests validate layout geometry and label rendering
// without a network connection. Placeholder rendering is an intentional fixture.
//
// SimulatedSectionRow mirrors the exact hub-row layout in PlinxHomeView:
// a bold title above a horizontal array of cards at the correct cardWidth.
//
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
@testable import PlinxUI

// MARK: - Aspect ratio constants (match PlinxHomeView.mediaCard logic)

extension CGFloat {
    /// Portrait aspect ratio used by movie / TV show / episode cards.
    static let portraitCard: CGFloat = 2.0 / 3.0
    /// Landscape 16:9 aspect ratio used by clip / YouTube / "Other Videos" cards.
    static let landscapeCard: CGFloat = 16.0 / 9.0
}

// MARK: - Card factory
//
// @MainActor required because PlinxMediaCard is a SwiftUI View, which is
// @MainActor-isolated. Static computed properties are used (not stored `let`
// constants) so each access is evaluated on the main actor.

@MainActor
enum ContentTypeFixtures {

    // ────────────────────────────────────────────────────────────────────────
    // MOVIES — portrait cards, subtitle = release year
    // ────────────────────────────────────────────────────────────────────────

    static var movieCards: [PlinxMediaCard] {[
        PlinxMediaCard(title: "Encanto",       subtitle: "2021", imageURL: nil),
        PlinxMediaCard(title: "Inside Out 2",  subtitle: "2024", imageURL: nil),
        PlinxMediaCard(title: "The Lion King", subtitle: "1994", imageURL: nil),
        PlinxMediaCard(title: "Moana 2",       subtitle: "2024", imageURL: nil),
        PlinxMediaCard(title: "Brave",         subtitle: "2012", imageURL: nil),
    ]}

    static func movieCard(
        title: String = "Encanto",
        subtitle: String? = "2021",
        progress: Double? = nil
    ) -> PlinxMediaCard {
        PlinxMediaCard(
            title: title,
            subtitle: subtitle,
            imageURL: nil,
            progress: progress,
            aspectRatio: .portraitCard
        )
    }

    // ────────────────────────────────────────────────────────────────────────
    // TV SHOWS — portrait cards, subtitle = season count
    // ────────────────────────────────────────────────────────────────────────

    static var tvShowCards: [PlinxMediaCard] {[
        PlinxMediaCard(title: "Bluey",         subtitle: "3 Seasons",  imageURL: nil),
        PlinxMediaCard(title: "Sesame Street", subtitle: "54 Seasons", imageURL: nil),
        PlinxMediaCard(title: "PAW Patrol",    subtitle: "10 Seasons", imageURL: nil),
        PlinxMediaCard(title: "Peppa Pig",     subtitle: "7 Seasons",  imageURL: nil),
        PlinxMediaCard(title: "Pokémon",       subtitle: "22 Seasons", imageURL: nil),
    ]}

    static func tvCard(
        title: String = "Bluey",
        subtitle: String? = "3 Seasons"
    ) -> PlinxMediaCard {
        PlinxMediaCard(title: title, subtitle: subtitle, imageURL: nil, aspectRatio: .portraitCard)
    }

    // ────────────────────────────────────────────────────────────────────────
    // EPISODES — portrait cards with watch progress (continue-watching hub)
    // ────────────────────────────────────────────────────────────────────────

    static var episodeCards: [PlinxMediaCard] {[
        PlinxMediaCard(title: "Bluey",      subtitle: "S3 • E12 · Stories",     imageURL: nil, progress: 0.45),
        PlinxMediaCard(title: "PAW Patrol", subtitle: "S4 • E2 · Mission PAW",  imageURL: nil, progress: 0.67),
        PlinxMediaCard(title: "Peppa Pig",  subtitle: "S2 • E6 · Camping",      imageURL: nil, progress: 0.15),
        PlinxMediaCard(title: "Bluey",      subtitle: "S3 • E13 · Neighbours",  imageURL: nil, progress: 0.90),
    ]}

    static func episodeCard(
        show: String = "Bluey",
        episodeInfo: String? = "S3 • E12",
        progress: Double = 0.45
    ) -> PlinxMediaCard {
        PlinxMediaCard(
            title: show,
            subtitle: episodeInfo,
            imageURL: nil,
            progress: progress,
            aspectRatio: .portraitCard
        )
    }

    // ────────────────────────────────────────────────────────────────────────
    // CLIPS / YOUTUBE ("Other Videos") — LANDSCAPE 16:9 cards
    //
    // This is the critical variant: Plex "clip" type items must render with
    // landscape thumbnails (16:9), NOT the portrait 2:3 used for movies/TV.
    // ────────────────────────────────────────────────────────────────────────

    static var clipCards: [PlinxMediaCard] {[
        PlinxMediaCard(title: "How Rainbows Form",     subtitle: "Educational",    imageURL: nil, aspectRatio: .landscapeCard),
        PlinxMediaCard(title: "Baby Animals Learning", subtitle: "Discovery Kids", imageURL: nil, aspectRatio: .landscapeCard),
        PlinxMediaCard(title: "Science Fun for Kids",  subtitle: "Fun Learning",   imageURL: nil, aspectRatio: .landscapeCard),
        PlinxMediaCard(title: "Animated Alphabet",     subtitle: "ABCs + Animals", imageURL: nil, aspectRatio: .landscapeCard),
        PlinxMediaCard(title: "Space for Young Minds", subtitle: "NASA Jr.",       imageURL: nil, aspectRatio: .landscapeCard),
    ]}

    static func clipCard(
        title: String = "How Rainbows Form",
        subtitle: String? = "Educational",
        progress: Double? = nil
    ) -> PlinxMediaCard {
        PlinxMediaCard(
            title: title,
            subtitle: subtitle,
            imageURL: nil,
            progress: progress,
            aspectRatio: .landscapeCard
        )
    }

    // ────────────────────────────────────────────────────────────────────────
    // MIXED — portrait + landscape interleaved (for mixed-section tests)
    // ────────────────────────────────────────────────────────────────────────

    static var mixedMoviesAndTV: [PlinxMediaCard] {
        Array(zip(movieCards, tvShowCards).flatMap { [$0.0, $0.1] }.prefix(6))
    }
}

// MARK: - SimulatedSectionRow
//
// UIKit types (UIColor.systemBackground) require the UIKit guard.

#if canImport(UIKit)
import UIKit

/// Renders a hub section row exactly as PlinxHomeView does:
/// a bold title header above a horizontal strip of cards.
///
/// - `layout: .portrait`  → 110pt-wide cards (movies / TV / episodes)
/// - `layout: .landscape` → 200pt-wide cards (clips / YouTube)
///
/// Uses `HStack` (not `ScrollView`) for deterministic snapshot geometry.
struct SimulatedSectionRow: View {
    enum Layout { case portrait, landscape }

    let title: String
    let cards: [PlinxMediaCard]
    let layout: Layout

    var cardWidth: CGFloat { layout == .landscape ? 200 : 110 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)

            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(cards.prefix(4).enumerated()), id: \.offset) { _, card in
                    card
                        .frame(width: cardWidth)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground))
    }
}
#endif
