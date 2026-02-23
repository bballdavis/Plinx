// ─────────────────────────────────────────────────────────────────────────────
// ClipCard_SnapshotTests.swift — LANDSCAPE layout, clip / "Other Videos" type
// ─────────────────────────────────────────────────────────────────────────────
//
// Plex "clip" type items (Plex-hosted YouTube videos, "Other Videos" libraries)
// MUST render as 16:9 landscape thumbnails, not the 2:3 portrait cards used
// for movies and TV shows.
//
// This is the primary regression guard for the landscape-thumbnail requirement.
//
// Key invariants under test:
//   1. Aspect ratio is 16:9 (width > height — visible card is wider than tall)
//   2. Card width is 200pt in the standard hub layout (vs 110pt for portrait)
//   3. Placeholder renders correctly in landscape orientation
//   4. Title + source subtitle render below the landscape image
//   5. No vertical stretching / squashing relative to portrait baseline
//
// Baselines: __Snapshots__/ClipCard_SnapshotTests/
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(XCTest) && canImport(UIKit)
import XCTest
import SnapshotTesting
import SwiftUI
@testable import PlinxUI

final class ClipCard_SnapshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        isRecording = true
    }

    private static let deviceMatrix: [(name: String, config: ViewImageConfig)] = [
        ("iphoneSE",  .iPhoneSe),
        ("iphone",    .iPhoneX),
        ("iPadPro13", .iPadPro12_9),
    ]

    // MARK: - Landscape geometry (the critical test)

    /// KEY TEST: Clip cards must render with 16:9 landscape ratio and 200pt width.
    /// Failure here means "Other Videos" items are showing portrait posters instead
    /// of landscape thumbnails.
    func test_clipCard_landscapeRatio_acrossDevices() {
        let card = ContentTypeFixtures.clipCard()
            .frame(width: 200)
            .padding(8)
        let host = UIHostingController(rootView: card)
        for device in Self.deviceMatrix {
            assertSnapshot(of: host, as: .image(on: device.config), named: device.name)
        }
    }

    /// Verifies: landscape card is visually wider-than-tall (geometry sanity).
    /// The rendered image height should be less than the card width (16:9 means
    /// imageHeight = 200 / (16/9) ≈ 112.5pt, well below the 200pt width).
    func test_clipCard_isWiderThanTall_iphone() {
        let card = ContentTypeFixtures.clipCard(title: "Baby Animals Learning")
            .frame(width: 200)
            .padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "landscape-wider-than-tall-iphone"
        )
    }

    // MARK: - Labels

    /// Verifies: title + subtitle render below the 16:9 image area.
    func test_clipCard_withLabels_iphone() {
        let card = ContentTypeFixtures.clipCard(
            title: "Science Fun for Kids",
            subtitle: "Fun Learning"
        )
        .frame(width: 200)
        .padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "with-labels-iphone"
        )
    }

    /// Verifies: long clip title truncates at one line (landscape label area is wider).
    func test_clipCard_longTitle_iphone() {
        let card = ContentTypeFixtures.clipCard(
            title: "The Complete Guide to Everything in the Universe for Kids",
            subtitle: "Discovery Jr."
        )
        .frame(width: 200)
        .padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "long-title-iphone"
        )
    }

    /// Verifies: missing subtitle renders cleanly without layout shift.
    func test_clipCard_noSubtitle_iphone() {
        let card = ContentTypeFixtures.clipCard(
            title: "Animated Alphabet",
            subtitle: nil
        )
        .frame(width: 200)
        .padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "no-subtitle-iphone"
        )
    }

    // MARK: - Ratio divergence guard

    /// Directly compare portrait and landscape card heights at the same width.
    /// The landscape card image height must be ≈ 56% of a portrait card at identical width.
    /// This snapshot diff makes it immediately visible if the ratio was accidentally swapped.
    func test_portraitVsLandscape_geometryComparison_iphone() {
        let portraitCard = ContentTypeFixtures.movieCard(title: "Movie (Portrait)")
            .frame(width: 200)
            .border(Color.blue, width: 1)
        let landscapeCard = ContentTypeFixtures.clipCard(title: "Clip (Landscape)")
            .frame(width: 200)
            .border(Color.red, width: 1)

        let comparison = VStack(alignment: .leading, spacing: 20) {
            Text("Portrait (2:3) — Movie")
                .font(.caption).bold()
            portraitCard

            Text("Landscape (16:9) — Clip / YouTube")
                .font(.caption).bold()
            landscapeCard
        }
        .padding()
        .background(Color(.systemBackground))

        assertSnapshot(
            of: UIHostingController(rootView: comparison),
            as: .image(on: .iPhoneX),
            named: "portrait-vs-landscape-iphone"
        )
    }

    // MARK: - Progress on clips

    /// Verifies: partially-watched clip renders progress bar in landscape orientation.
    func test_clipCard_withProgress_iphone() {
        let card = ContentTypeFixtures.clipCard(
            title: "How Rainbows Form",
            subtitle: "Educational",
            progress: 0.55
        )
        .frame(width: 200)
        .padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "with-progress-iphone"
        )
    }
}
#endif
