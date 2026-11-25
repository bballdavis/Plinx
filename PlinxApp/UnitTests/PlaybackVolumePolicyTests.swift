import XCTest
@testable import Plinx

@MainActor
final class PlaybackVolumePolicyTests: XCTestCase {
    func test_clampsConfiguredMaximumVolume() {
        XCTAssertEqual(PlaybackSettings.clampVolumePercent(135), 100)
        XCTAssertEqual(PlaybackSettings.clampVolumePercent(-5), 0)
        XCTAssertEqual(PlaybackSettings.clampVolumePercent(70), 70)
    }

    // MARK: - PlayerController volume cap

    func test_playerStartsAtTheDefaultCapBeforeTheSettingArrives() {
        let controller = PlayerController()

        XCTAssertEqual(controller.maximumVolume, PlaybackSettings.defaultMaximumVolume, accuracy: 0.001)
        XCTAssertEqual(controller.volume, PlaybackSettings.defaultMaximumVolume, accuracy: 0.001)
        XCTAssertEqual(controller.outputVolume, PlaybackSettings.defaultMaximumVolume, accuracy: 0.001)
    }

    func test_capOfOneYieldsFullEngineVolume() {
        let controller = PlayerController()

        controller.setMaximumVolume(1.0)

        XCTAssertEqual(controller.volume, 1.0, accuracy: 0.001)
        XCTAssertEqual(controller.outputVolume, 1.0, accuracy: 0.001)
    }

    func test_volumeFollowsTheCapUpAndDownUntilSomethingSetsIt() {
        let controller = PlayerController()

        controller.setMaximumVolume(0.8)
        XCTAssertEqual(controller.outputVolume, 0.8, accuracy: 0.001)
        controller.setMaximumVolume(0.4)
        XCTAssertEqual(controller.outputVolume, 0.4, accuracy: 0.001)
        controller.setMaximumVolume(0.9)
        XCTAssertEqual(controller.volume, 0.9, accuracy: 0.001)
        XCTAssertEqual(controller.outputVolume, 0.9, accuracy: 0.001)
    }

    func test_setVolumeAboveTheCapIsClampedToTheCap() {
        let controller = PlayerController()
        controller.setMaximumVolume(0.5)

        controller.setVolume(1.0)

        XCTAssertEqual(controller.volume, 0.5, accuracy: 0.001)
        XCTAssertEqual(controller.outputVolume, 0.5, accuracy: 0.001)
    }

    func test_loweringTheCapLowersALouderVolume() {
        let controller = PlayerController()
        controller.setMaximumVolume(1.0)
        controller.setVolume(0.8)

        controller.setMaximumVolume(0.3)

        XCTAssertEqual(controller.volume, 0.3, accuracy: 0.001)
        XCTAssertEqual(controller.outputVolume, 0.3, accuracy: 0.001)

        // A volume someone set is not raised again when the cap goes back up.
        controller.setMaximumVolume(1.0)
        XCTAssertEqual(controller.volume, 0.3, accuracy: 0.001)
        XCTAssertEqual(controller.outputVolume, 0.3, accuracy: 0.001)
    }

    func test_capIsClampedToTheUnitRange() {
        let controller = PlayerController()

        controller.setMaximumVolume(1.5)
        XCTAssertEqual(controller.maximumVolume, 1.0, accuracy: 0.001)
        XCTAssertEqual(controller.outputVolume, 1.0, accuracy: 0.001)

        controller.setMaximumVolume(-0.2)
        XCTAssertEqual(controller.maximumVolume, 0, accuracy: 0.001)
        XCTAssertEqual(controller.volume, 0, accuracy: 0.001)
        XCTAssertEqual(controller.outputVolume, 0, accuracy: 0.001)
    }

    func test_fadeScalesTheCappedOutputWithoutChangingTheVolume() {
        let controller = PlayerController()
        controller.setMaximumVolume(0.6)

        controller.setVolumeAttenuation(0.5)

        XCTAssertEqual(controller.volume, 0.6, accuracy: 0.001)
        XCTAssertEqual(controller.outputVolume, 0.3, accuracy: 0.001)
    }

    func test_muteSurvivesACapChangeAndUnmuteReturnsToTheCap() {
        let controller = PlayerController()
        controller.setMaximumVolume(0.6)

        controller.toggleMute()
        XCTAssertTrue(controller.isMuted)
        controller.setMaximumVolume(0.9)
        XCTAssertTrue(controller.isMuted)
        XCTAssertEqual(controller.outputVolume, 0, accuracy: 0.001)

        controller.toggleMute()
        XCTAssertEqual(controller.volume, 0.9, accuracy: 0.001)
        XCTAssertEqual(controller.outputVolume, 0.9, accuracy: 0.001)
    }

    func test_zeroCapSilencesThePlayerUntilTheCapIsRaised() {
        let controller = PlayerController()

        controller.setMaximumVolume(0)
        XCTAssertTrue(controller.isMuted)
        controller.toggleMute()
        XCTAssertEqual(controller.outputVolume, 0, accuracy: 0.001)

        controller.setMaximumVolume(0.5)
        XCTAssertEqual(controller.volume, 0.5, accuracy: 0.001)
        XCTAssertEqual(controller.outputVolume, 0.5, accuracy: 0.001)
    }
}
