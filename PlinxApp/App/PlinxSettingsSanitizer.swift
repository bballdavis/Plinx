import Foundation

@MainActor
enum PlinxSettingsSanitizer {
    /// Seerr discovery/request flows are not part of the first Plinx release
    /// because they do not yet pass through Plinx's parental authorization.
    static func disableUnsupportedExternalDiscovery(_ settingsManager: SettingsManager) {
        guard settingsManager.interface.displaySeerrDiscoverTab else { return }
        settingsManager.setDisplaySeerrDiscoverTab(false)
    }
}
