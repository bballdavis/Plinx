// ─────────────────────────────────────────────────────────────────────────────
// MovieCard_SnapshotTests.swift — Portrait layout, movie content type
// ─────────────────────────────────────────────────────────────────────────────
//
// Movies are always shown in portrait cards (2:3 aspect ratio). These tests
// verify that the geometry, title + year label, and placeholder rendering
// are correct at all three supported device sizes.
//
// Baselines live in __Snapshots__/MovieCard_SnapshotTests/
// First-run recording: set `isRecording = true`, run on iPhone 16 sim, commit.
//
// References: development/UI_TESTING_STRATEGY.md — "Component rendering" layer
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(XCTest) && canImport(UIKit)
import XCTest
import SnapshotTesting
import SwiftUI
@testable import PlinxUI

final class MovieCard_SnapshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Flip to `true` to regenerate baselines, commit __Snapshots__/, flip back.
        // isRecording = true
    }

    private static let deviceMatrix: [(name: String, config: ViewImageConfig)] = [
        ("iphoneSE",  .iPhoneSe),
        ("iphone",    .iPhoneX),
        ("iPadPro13", .iPadPro12_9),
    ]

    // MARK: - Portrait geometry

    /// Verifies: portrait 2:3 ratio renders correctly across all device classes.
    func test_movieCard_portraitRatio_acrossDevices() {
        let card = ContentTypeFixtures.movieCard()
            .frame(width: 110)
            .padding(8)
        let host = UIHostingController(rootView: card)
        for device in Self.deviceMatrix {
            assertSnapshot(of: host, as: .image(on: device.config), named: device.name)
        }
    }

    // MARK: - Labels

    /// Verifies: title + year subtitle render without truncation at 110pt card width.
    func test_movieCard_withYearSubtitle_iphone() {
        let card = ContentTypeFixtures.movieCard(title: "The Lion King", subtitle: "1994")
            .frame(width: 110)
            .padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "with-year-iphone"
        )
    }

    /// Verifies: long titles are clamped to two lines without layout overflow.
    func test_movieCard_longTitle_truncatesGracefully() {
        let card = ContentTypeFixtures.movieCard(
            title: "The Very Long Feature Film Documentary Title",
            subtitle: "2023"
        )
        .frame(width: 110)
        .padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "long-title-iphone"
        )
    }

    /// Verifies: missing subtitle renders without empty-space gap.
    func test_movieCard_noSubtitle_iphone() {
        let card = ContentTypeFixtures.movieCard(title: "Brave", subtitle: nil)
            .frame(width: 110)
            .padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "no-subtitle-iphone"
        )
    }

    // MARK: - Placeholder

    /// Verifies: nil imageURL shows placeholder, not a crash or blank space.
    func test_movieCard_nilImage_showsPlaceholder_acrossDevices() {
        let card = ContentTypeFixtures.movieCard(title: "Encanto")
            .frame(width: 110)
            .padding(8)
        let host = UIHostingController(rootView: card)
        for device in Self.deviceMatrix {
            assertSnapshot(of: host, as: .image(on: device.config), named: "placeholder-\(device.name)")
        }
    }
}
#endif
