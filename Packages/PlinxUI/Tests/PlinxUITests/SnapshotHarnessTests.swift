// ─────────────────────────────────────────────────────────────────────────────
// SnapshotHarnessTests.swift
// ─────────────────────────────────────────────────────────────────────────────
//
// Pixel-diff snapshot tests for PlinxUI components across three device sizes:
//   iphoneSE  — compact width (320pt), catches text/layout truncation
//   iphone    — standard width (375pt)
//   iPadPro13 — regular width (1024pt), catches iPad-specific layout breaks
//
// FIRST RUN: set `isRecording = true` in setUp(), run once on iPhone 15
// simulator, commit __Snapshots__/, then set back to false.
//
// References: development/UI_TESTING_STRATEGY.md — "Component rendering" layer
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(XCTest) && canImport(UIKit)
import XCTest
import SnapshotTesting
import SwiftUI
@testable import PlinxUI

@MainActor
final class SnapshotHarnessTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Flip to `true` to regenerate baselines, commit __Snapshots__/, flip back.
        // isRecording = true
    }

    // MARK: - Device matrix
    //
    // Three configs cover compact (SE), standard (X), and regular-width (iPad).
    // Every multi-device test runs all three in one pass.

    private static let deviceMatrix: [(name: String, config: ViewImageConfig)] = [
        ("iphoneSE",  .iPhoneSe),
        ("iphone",    .iPhoneX),
        ("iPadPro13", .iPadPro12_9),
    ]

    // MARK: - PlinxMediaCard
    //
    // Verifies: placeholder visible when imageURL is nil, progress bar renders,
    // overflowing progress is clamped to full bar width.

    func test_mediaCard_placeholder_acrossDevices() {
        let card = PlinxMediaCard(
            title: "Adventure Time",
            subtitle: "Season 1, Ep 1",
            imageURL: nil
        )
        .frame(width: 120)
        .padding(8)
        let host = UIHostingController(rootView: card)
        for device in Self.deviceMatrix {
            assertSnapshot(of: host, as: .image(on: device.config), named: device.name)
        }
    }

    func test_mediaCard_withProgress_iphone() {
        let card = PlinxMediaCard(
            title: "Now Watching",
            subtitle: nil,
            imageURL: nil,
            progress: 0.5
        )
        .frame(width: 120)
        .padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "progress-50pct"
        )
    }

    func test_mediaCard_clampedProgress_iphone() {
        // progress > 1.0 should render as a full bar, not overflow.
        let card = PlinxMediaCard(title: "Completed", imageURL: nil, progress: 1.5)
            .frame(width: 120).padding(8)
        assertSnapshot(
            of: UIHostingController(rootView: card),
            as: .image(on: .iPhoneX),
            named: "progress-full-clamped"
        )
    }

    // MARK: - PlinxErrorView
    //
    // Verifies: message text is visible, retry button present/absent.

    func test_errorView_withRetry_acrossDevices() {
        let view = PlinxErrorView(message: "Could not load content.") { /* retry */ }
        let host = UIHostingController(rootView: view)
        for device in Self.deviceMatrix {
            assertSnapshot(of: host, as: .image(on: device.config), named: device.name)
        }
    }

    func test_errorView_noRetryButton() {
        let view = PlinxErrorView(message: "No connection — check your network.")
        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: .iPhoneX),
            named: "no-retry-iphone"
        )
    }

    // MARK: - BabyLockModifier
    //
    // Verifies: badge is visible when locked; no overlay when unlocked.
    // The badge must appear on all three device sizes (including iPad).

    func test_babyLock_enabled_showsBadge_acrossDevices() {
        let content = Text("Kids content")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.blue.opacity(0.15))
            .modifier(BabyLockModifier(isEnabled: .constant(true)))
        let host = UIHostingController(rootView: content)
        for device in Self.deviceMatrix {
            assertSnapshot(of: host, as: .image(on: device.config), named: device.name)
        }
    }

    func test_babyLock_disabled_noOverlay() {
        let content = Text("Visible to user")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.green.opacity(0.15))
            .modifier(BabyLockModifier(isEnabled: .constant(false)))
        assertSnapshot(
            of: UIHostingController(rootView: content),
            as: .image(on: .iPhoneX),
            named: "unlocked-iphone"
        )
    }
}
#endif
