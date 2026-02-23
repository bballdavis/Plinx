// ─────────────────────────────────────────────────────────────────────────────
// ContinueWatching_SnapshotTests.swift — Continue-watching hub rendering
// ─────────────────────────────────────────────────────────────────────────────
//
// The Continue Watching hub shows episode cards arranged in a LANDSCAPE row
// (PlinxHomeView uses layout: .landscape for continueWatching).
// Each card displays a progress bar indicating the user's watch position.
//
// Key invariants:
//   - Cards render at 200pt wide with 16:9 ratio (landscape layout)
//   - Progress bar appears at the correct proportional width (45%, 67%, etc.)
//   - Near-complete (90%) shows a nearly full bar
//   - Progress > 1.0 clamps — no overflow beyond card edge
//   - Zero / nil progress → no bar rendered
//   - Show title + S•E label renders below the thumbnail
//
// Baselines: __Snapshots__/ContinueWatching_SnapshotTests/
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(XCTest) && canImport(UIKit)
import XCTest
import SnapshotTesting
import SwiftUI
@testable import PlinxUI

@MainActor
final class ContinueWatching_SnapshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // isRecording = true
    }

    private static let deviceMatrix: [(name: String, config: ViewImageConfig)] = [
        ("iphoneSE",  .iPhoneSe),
        ("iphone",    .iPhoneX),
        ("iPadPro13", .iPadPro12_9),
    ]

    // MARK: - Individual progress states

    /// Verifies: 45% progress — bar fills roughly the left half of the card.
    func test_continueWatching_45pctProgress_acrossDevices() {
        let card = PlinxMediaCard(
            title: "Bluey",
            subtitle: "S3 • E12 · Stories",
            imageURL: nil,
            progress: 0.45,
            aspectRatio: .landscapeCard
        )
        .frame(width: 200)
        .padding(8)
        let host = UIHostingController(rootView: card)
        for device in Self.deviceMatrix {
            assertSnapshot(of: host, as: .image(on: device.config), named: device.name)
        }
    }

    /// Verifies: 67% progress — bar fills just under two-thirds of the card.
    func test_continueWatching_67pctProgress_iphone() {
        let card = PlinxMediaCard(
            title: "PAW Patrol",
            subtitle: "S4 • E2 · Mission PAW",
            imageURL: nil,
            progress: 0.67,
            aspectRatio: .landscapeCard
        )
        .frame(width: 200)
        .padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "progress-67pct-iphone"
        )
    }

    /// Verifies: 90% progress — bar is nearly full, clearly visible.
    func test_continueWatching_90pctProgress_iphone() {
        let card = PlinxMediaCard(
            title: "Bluey",
            subtitle: "S3 • E13 · Neighbours",
            imageURL: nil,
            progress: 0.90,
            aspectRatio: .landscapeCard
        )
        .frame(width: 200)
        .padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "progress-90pct-iphone"
        )
    }

    /// Verifies: progress = 1.0 → full bar, no overflow.
    func test_continueWatching_100pctProgress_iphone() {
        let card = PlinxMediaCard(
            title: "Peppa Pig",
            subtitle: "S2 • E6 · Camping",
            imageURL: nil,
            progress: 1.0,
            aspectRatio: .landscapeCard
        )
        .frame(width: 200)
        .padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "progress-100pct-iphone"
        )
    }

    /// Verifies: progress > 1.0 is clamped — bar must NOT exceed card width.
    func test_continueWatching_overflowProgress_clamps_iphone() {
        let card = PlinxMediaCard(
            title: "PAW Patrol",
            subtitle: "S5 • E1",
            imageURL: nil,
            progress: 1.8,   // intentionally over-full
            aspectRatio: .landscapeCard
        )
        .frame(width: 200)
        .padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "progress-clamped-iphone"
        )
    }

    /// Verifies: no progress bar renders when progress is nil.
    func test_continueWatching_nilProgress_noBar_iphone() {
        let card = PlinxMediaCard(
            title: "Bluey",
            subtitle: "S1 • E1 · Mum School",
            imageURL: nil,
            progress: nil,
            aspectRatio: .landscapeCard
        )
        .frame(width: 200)
        .padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "no-progress-iphone"
        )
    }

    // MARK: - Section row

    /// Verifies: the full Continue Watching hub row renders at landscape layout.
    func test_continueWatchingRow_landscapeCards_acrossDevices() {
        let cards: [PlinxMediaCard] = [
            PlinxMediaCard(title: "Bluey",      subtitle: "S3 • E12", imageURL: nil, progress: 0.45, aspectRatio: .landscapeCard),
            PlinxMediaCard(title: "PAW Patrol", subtitle: "S4 • E2",  imageURL: nil, progress: 0.67, aspectRatio: .landscapeCard),
            PlinxMediaCard(title: "Peppa Pig",  subtitle: "S2 • E6",  imageURL: nil, progress: 0.15, aspectRatio: .landscapeCard),
        ]
        let row = SimulatedSectionRow(
            title: "Continue Watching",
            cards: cards,
            layout: .landscape
        )
        let host = UIHostingController(rootView: row)
        for device in Self.deviceMatrix {
            assertSnapshot(of: host, as: .image(on: device.config), named: device.name)
        }
    }
}
#endif
