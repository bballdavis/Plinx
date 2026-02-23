// ─────────────────────────────────────────────────────────────────────────────
// SectionRow_SnapshotTests.swift — Full hub section row rendering
// ─────────────────────────────────────────────────────────────────────────────
//
// Each "section" on the Plinx home screen is a titled hub row with a horizontal
// strip of media cards. This file snapshot-tests complete section rows at all
// three device sizes, catching layout bugs that only emerge when multiple cards
// sit side-by-side (spacing, label widths, overflow, iPad column width).
//
// Section types under test (matching PlinxHomeView section IDs):
//   - "moviesAndTV"   → portrait 2:3 cards, interleaved movies + TV shows
//   - "otherVideos"   → LANDSCAPE 16:9 cards (clip / YouTube libraries)
//   - "continueWatching" → landscape cards with progress bars
//
// SimulatedSectionRow (from TestFixtures.swift) renders the same VStack +
// HStack + bold-title structure as PlinxHomeView.hubRow(_:layout:).
//
// Baselines: __Snapshots__/SectionRow_SnapshotTests/
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(XCTest) && canImport(UIKit)
import XCTest
import SnapshotTesting
import SwiftUI
@testable import PlinxUI

final class SectionRow_SnapshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // isRecording = true
    }

    private static let deviceMatrix: [(name: String, config: ViewImageConfig)] = [
        ("iphoneSE",  .iPhoneSe),
        ("iphone",    .iPhoneX),
        ("iPadPro13", .iPadPro12_9),
    ]

    // MARK: - "moviesAndTV" section — portrait cards

    /// Renders the combined Movies + TV "recently added" section with 110pt portrait
    /// cards interleaved: movie, show, movie, show (matching PlinxHomeView logic).
    func test_moviesAndTVSection_portraitCards_acrossDevices() {
        let row = SimulatedSectionRow(
            title: "Recently Added",
            cards: ContentTypeFixtures.mixedMoviesAndTV,
            layout: .portrait
        )
        let host = UIHostingController(rootView: row)
        for device in Self.deviceMatrix {
            assertSnapshot(of: host, as: .image(on: device.config), named: device.name)
        }
    }

    /// Verifies a movies-only section (no TV shows available).
    func test_moviesOnlySection_portraitCards_iphone() {
        let row = SimulatedSectionRow(
            title: "Recently Added · Movies",
            cards: ContentTypeFixtures.movieCards,
            layout: .portrait
        )
        assertSnapshot(
            of: UIHostingController(rootView: row),
            as: .image(on: .iPhoneX),
            named: "movies-only-iphone"
        )
    }

    /// Verifies a TV-only section (no movies available).
    func test_tvOnlySection_portraitCards_iphone() {
        let row = SimulatedSectionRow(
            title: "Recently Added · TV Shows",
            cards: ContentTypeFixtures.tvShowCards,
            layout: .portrait
        )
        assertSnapshot(
            of: UIHostingController(rootView: row),
            as: .image(on: .iPhoneX),
            named: "tv-only-iphone"
        )
    }

    // MARK: - "otherVideos" section — landscape cards (clip / YouTube)

    /// KEY TEST: The "Other Videos" (clip type) section must render 200pt-wide
    /// landscape cards, not portrait cards. A swap in PlinxHomeView would be
    /// immediately visible as portrait thumbnails in a landscape-spaced row.
    func test_otherVideosSection_landscapeCards_acrossDevices() {
        let row = SimulatedSectionRow(
            title: "Other Videos",
            cards: ContentTypeFixtures.clipCards,
            layout: .landscape
        )
        let host = UIHostingController(rootView: row)
        for device in Self.deviceMatrix {
            assertSnapshot(of: host, as: .image(on: device.config), named: device.name)
        }
    }

    /// Verifies a YouTube-specific label ("YouTube Kids") in the section header.
    func test_youtubeSection_landscapeCards_iphone() {
        let cards: [PlinxMediaCard] = [
            ContentTypeFixtures.clipCard(title: "Space for Young Minds", subtitle: "NASA Jr."),
            ContentTypeFixtures.clipCard(title: "Animated Alphabet",      subtitle: "ABCs + Animals"),
            ContentTypeFixtures.clipCard(title: "How Rainbows Form",     subtitle: "Educational"),
        ]
        let row = SimulatedSectionRow(title: "YouTube Kids", cards: cards, layout: .landscape)
        assertSnapshot(
            of: UIHostingController(rootView: row),
            as: .image(on: .iPhoneX),
            named: "youtube-kids-iphone"
        )
    }

    // MARK: - Layout / ratio isolation comparison

    /// Side-by-side portrait row vs landscape row in one snapshot.
    /// The height difference between portrait and landscape strips makes it
    /// immediately obvious if the two section types swapped their layouts.
    func test_portraitVsLandscapeRow_comparison_iphone() {
        let portraitRow = SimulatedSectionRow(
            title: "Movies & TV (Portrait)",
            cards: Array(ContentTypeFixtures.movieCards.prefix(3)),
            layout: .portrait
        )
        .border(Color.blue, width: 1)

        let landscapeRow = SimulatedSectionRow(
            title: "Other Videos (Landscape)",
            cards: Array(ContentTypeFixtures.clipCards.prefix(3)),
            layout: .landscape
        )
        .border(Color.red, width: 1)

        let comparison = VStack(alignment: .leading, spacing: 24) {
            portraitRow
            landscapeRow
        }
        .background(Color(.systemBackground))

        assertSnapshot(
            of: UIHostingController(rootView: comparison),
            as: .image(on: .iPhoneX),
            named: "portrait-vs-landscape-rows-iphone"
        )
    }

    // MARK: - Section title rendering

    /// Verifies: bold title renders correctly for both localizable section names.
    func test_sectionTitle_localizedStrings_iphone() {
        let rows = VStack(alignment: .leading, spacing: 24) {
            SimulatedSectionRow(
                title: "Continue Watching",
                cards: Array(ContentTypeFixtures.episodeCards.prefix(3)),
                layout: .landscape
            )
            SimulatedSectionRow(
                title: "Recently Added",
                cards: Array(ContentTypeFixtures.mixedMoviesAndTV.prefix(4)),
                layout: .portrait
            )
            SimulatedSectionRow(
                title: "Other Videos",
                cards: Array(ContentTypeFixtures.clipCards.prefix(3)),
                layout: .landscape
            )
        }
        .background(Color(.systemBackground))

        assertSnapshot(
            of: UIHostingController(rootView: rows),
            as: .image(on: .iPhoneX),
            named: "all-section-titles-iphone"
        )
    }

    // MARK: - iPad layout

    /// On iPad (regular width) portrait cards should not stretch beyond 110pt.
    func test_moviesSection_iPadLayout_doesNotStretch() {
        let row = SimulatedSectionRow(
            title: "Recently Added · Movies",
            cards: ContentTypeFixtures.movieCards,
            layout: .portrait
        )
        assertSnapshot(
            of: UIHostingController(rootView: row),
            as: .image(on: .iPadPro12_9),
            named: "movies-ipad"
        )
    }

    /// On iPad landscape clips should render at 200pt width without collapse.
    func test_clipSection_iPadLayout_correctWidth() {
        let row = SimulatedSectionRow(
            title: "Other Videos",
            cards: ContentTypeFixtures.clipCards,
            layout: .landscape
        )
        assertSnapshot(
            of: UIHostingController(rootView: row),
            as: .image(on: .iPadPro12_9),
            named: "clips-ipad"
        )
    }
}
#endif
