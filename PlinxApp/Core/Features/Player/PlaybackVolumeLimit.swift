import Foundation

/// Parent-set maximum playback volume (kid safety).
///
/// The limit lives in `PlaybackSettings.maxVolumePercent` (default 70 percent)
/// and both platforms' `PlayerView` push it to `PlayerController.setMaximumVolume`
/// when the player appears and whenever the setting changes.
extension SettingsManager {
    func setMaxVolumePercent(_ percent: Int) {
        updatePlayback { $0.maxVolumePercent = PlaybackSettings.clampVolumePercent(percent) }
    }
}
