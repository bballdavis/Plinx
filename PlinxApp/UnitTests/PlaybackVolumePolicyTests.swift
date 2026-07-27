import XCTest
@testable import Plinx

@MainActor
final class PlaybackVolumePolicyTests: XCTestCase {
    func test_clampsConfiguredMaximumVolume() {
        XCTAssertEqual(PlaybackSettings.clampVolumePercent(135), 100)
        XCTAssertEqual(PlaybackSettings.clampVolumePercent(-5), 0)
        XCTAssertEqual(PlaybackSettings.clampVolumePercent(70), 70)
    }
}
