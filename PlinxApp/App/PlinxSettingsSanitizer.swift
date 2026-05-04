import Foundation

@MainActor
enum PlinxSettingsSanitizer {
    /// Plinx excludes Strimr's VLC implementation and ships MPV as the supported internal player.
    /// Coerce legacy persisted VLC selection to MPV so playback controls (including max volume)
    /// remain functional after migrations from older settings payloads.
    static func enforceSupportedPlaybackPlayer(_ settingsManager: SettingsManager) {
        guard settingsManager.playback.player == .vlc else { return }
        settingsManager.setPlaybackPlayer(.mpv)
    }
}