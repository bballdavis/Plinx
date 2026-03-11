import XCTest
@testable import Plinx

@MainActor
final class SettingsManagerPlaybackTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsManagerPlaybackTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_maxVolumeDefaultsToSeventyPercent() {
        let settings = SettingsManager(userDefaults: defaults)

        XCTAssertEqual(settings.playback.maxVolumePercent, 70)
    }

    func test_missingStoredMaxVolumeDefaultsToSeventyPercent() {
        let stored = """
        {
          "playback": {
            "autoPlayNextEpisode": true,
            "seekBackwardSeconds": 10,
            "seekForwardSeconds": 10,
            "player": "mpv",
            "subtitleScale": 100
          },
          "interface": {},
          "downloads": {}
        }
        """
        defaults.set(Data(stored.utf8), forKey: "strimr.settings")

        let settings = SettingsManager(userDefaults: defaults)

        XCTAssertEqual(settings.playback.maxVolumePercent, 70)
    }

    func test_setMaxVolumeClampsAndPersists() {
        let settings = SettingsManager(userDefaults: defaults)

        settings.setMaxVolumePercent(130)

        XCTAssertEqual(settings.playback.maxVolumePercent, 100)

        let reloaded = SettingsManager(userDefaults: defaults)
        XCTAssertEqual(reloaded.playback.maxVolumePercent, 100)
    }
}
