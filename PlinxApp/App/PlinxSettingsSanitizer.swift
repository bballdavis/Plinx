import Foundation

@MainActor
enum PlinxSettingsSanitizer {
    static func applyPlinxDefaults(
        _ settingsManager: SettingsManager,
        userDefaults: UserDefaults = .standard
    ) {
        guard !hasPersistedDisplayCollections(in: userDefaults) else { return }
        settingsManager.setDisplayCollections(false)
    }

    /// Seerr discovery/request flows are not part of the first Plinx release
    /// because they do not yet pass through Plinx's parental authorization.
    static func disableUnsupportedExternalDiscovery(_ settingsManager: SettingsManager) {
        guard settingsManager.interface.displaySeerrDiscoverTab else { return }
        settingsManager.setDisplaySeerrDiscoverTab(false)
    }

    private static func hasPersistedDisplayCollections(in defaults: UserDefaults) -> Bool {
        guard let data = defaults.data(forKey: "strimr.settings"),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let interface = object["interface"] as? [String: Any]
        else {
            return false
        }
        return interface["displayCollections"] != nil
    }
}
