// ─────────────────────────────────────────────────────────────────────────────
// TVCard_SnapshotTests.swift — Portrait layout, TV show & episode types
// ─────────────────────────────────────────────────────────────────────────────
//
// TV shows and episodes use portrait cards (2:3 ratio). Episodes additionally
// carry a season/episode subtitle and an optional watch-progress bar.
//
// These tests verify:
//   - Portrait geometry is consistent with movie cards
//   - Season-count subtitle renders ("3 Seasons")
//   - S{n} • E{n} episode label fits at 110pt card width
//   - Progress bar does NOT appear on show cards (only on episode cards)
//
// Baselines: __Snapshots__/TVCard_SnapshotTests/
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(XCTest) && canImport(UIKit)
import XCTest
import SnapshotTesting
import SwiftUI
@testable import PlinxUI

final class TVCard_SnapshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // isRecording = true
    }

    private static let deviceMatrix: [(name: String, config: ViewImageConfig)] = [
        ("iphoneSE",  .iPhoneSe),
        ("iphone",    .iPhoneX),
        ("iPadPro13", .iPadPro12_9),
    ]

    // MARK: - TV Show cards (portrait, no progress)

    /// Verifies: portrait 2:3 geometry, season-count subtitle.
    func test_tvShowCard_portraitRatio_acrossDevices() {
        let card = ContentTypeFixtures.tvCard()
            .frame(width: 110)
            .padding(8)
        let host = UIHostingController(rootView: card)
        for device in Self.deviceMatrix {
            assertSnapshot(of: host, as: .image(on: device.config), named: device.name)
        }
    }

    /// Verifies: multi-word show title + long season count label both fit.
    func test_tvShowCard_longSeasonCount_iphone() {
        let card = ContentTypeFixtures.tvCard(title: "Sesame Street", subtitle: "54 Seasons")
            .frame(width: 110)
            .padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "many-seasons-iphone"
        )
    }

    /// Verifies: no progress bar appears on show cards.
    func test_tvShowCard_noProgressBar_iphone() {
        // PlinxMediaCard(progress: nil) must not render any progress bar element.
        let card = ContentTypeFixtures.tvCard(title: "PAW Patrol", subtitle: "10 Seasons")
            .frame(width: 110)
            .padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "no-progress-iphone"
        )
    }

    // MARK: - Episode cards (portrait, WITH progress)

    /// Verifies: episode card renders S/E subtitle and a progress bar at 45%.
    func test_episodeCard_withProgress_acrossDevices() {
        let card = ContentTypeFixtures.episodeCard(
            show: "Bluey",
            episodeInfo: "S3 • E12",
            progress: 0.45
        )
        .frame(width: 110)
        .padding(8)
        let host = UIHostingController(rootView: card)
        for device in Self.deviceMatrix {
            assertSnapshot(of: host, as: .image(on: device.config), named: device.name)
        }
    }

    /// Verifies: near-complete episode (90%) shows a nearly full progress bar.
    func test_episodeCard_highProgress_iphone() {
        let card = ContentTypeFixtures.episodeCard(
            show: "Bluey",
            episodeInfo: "S3 • E13",
            progress: 0.90
        )
        .frame(width: 110)
        .padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "progress-90pct-iphone"
        )
    }

    /// Verifies: progress > 1.0 is clamped and does not overflow the card width.
    func test_episodeCard_clampedProgress_iphone() {
        let card = ContentTypeFixtures.episodeCard(
            show: "PAW Patrol",
            episodeInfo: "S4 • E2",
            progress: 1.5   // over-full — must clamp to 100%
        )
        .frame(width: 110)
        .padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "progress-clamped-iphone"
        )
    }

    /// Verifies: zero progress does not render any bar element.
    func test_episodeCard_zeroProgress_noBar_iphone() {
        let card = ContentTypeFixtures.episodeCard(
            show: "Peppa Pig",
            episodeInfo: "S2 • E6",
            progress: 0.0
        )
        .frame(width: 110)
        .padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "progress-zero-iphone"
        )
    }
}
#endif
