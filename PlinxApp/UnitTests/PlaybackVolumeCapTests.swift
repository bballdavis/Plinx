import XCTest
@testable import Plinx

@MainActor
final class PlaybackVolumeCapTests: XCTestCase {
    func test_appliesClampedPlaybackGain() {
        let target = RecordingVolumeTarget()

        PlaybackVolumeCap.apply(135, to: target)
        PlaybackVolumeCap.apply(-5, to: target)
        PlaybackVolumeCap.apply(70, to: target)

        XCTAssertEqual(target.values, [100, 0, 70])
    }
}

@MainActor
private final class RecordingVolumeTarget: PlaybackVolumeApplying {
    private(set) var values: [Int] = []

    func setVolume(_ volumePercent: Int) {
        values.append(volumePercent)
    }
}
