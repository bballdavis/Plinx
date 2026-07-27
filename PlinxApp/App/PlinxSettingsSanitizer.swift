import Foundation

@MainActor
enum PlinxSettingsSanitizer {
    /// The first Plinx release ships MPV as its only player. Coerce legacy VLC
    /// and Infuse selections to MPV so content authorization and the app-level
    /// playback cap cannot be bypassed by handing playback to another app.
    static func enforceSupportedPlaybackPlayer(_ settingsManager: SettingsManager) {
        guard settingsManager.playback.player != .mpv else { return }
        settingsManager.setPlaybackPlayer(.mpv)
    }

    /// Seerr discovery/request flows are not part of the first Plinx release
    /// because they do not yet pass through Plinx's parental authorization.
    static func disableUnsupportedExternalDiscovery(_ settingsManager: SettingsManager) {
        guard settingsManager.interface.displaySeerrDiscoverTab else { return }
        settingsManager.setDisplaySeerrDiscoverTab(false)
    }
}
