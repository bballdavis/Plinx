import Foundation

/// Launch-time corrections that keep absorbed settings inside the Plinx
/// product scope, whatever an earlier build or a restored backup persisted.
@MainActor
enum PlinxSettingsSanitizer {
    static func applyPlinxDefaults(
        _ settingsManager: SettingsManager,
        userDefaults: UserDefaults = .standard
    ) {
        guard !hasPersistedDisplayCollections(in: userDefaults) else { return }
        settingsManager.setDisplayCollections(false)
    }

    /// Everything Plinx does not ship to kids yet: Seerr discovery, Live TV,
    /// and the absorbed settings Plinx hides from its settings screens.
    static func disableUnsupportedFeatures(_ settingsManager: SettingsManager) {
        disableUnsupportedExternalDiscovery(settingsManager)
        disableLiveTV(settingsManager)
        resetHiddenSettings(settingsManager)
    }

    /// Seerr discovery/request flows stay off until the Seerr kid model
    /// (per-kid Seerr user, certification filtering) lands; they do not yet
    /// pass through Plinx's parental authorization.
    static func disableUnsupportedExternalDiscovery(_ settingsManager: SettingsManager) {
        guard settingsManager.interface.displaySeerrDiscoverTab else { return }
        settingsManager.setDisplaySeerrDiscoverTab(false)
    }

    /// Live TV programs and channels carry no rating, so per-item filtering
    /// cannot fail closed (hard-fork decision D5). The safety boundary also
    /// turns the capability off; this keeps the startup tab from asking for it.
    static func disableLiveTV(_ settingsManager: SettingsManager) {
        guard settingsManager.interface.displayLiveTVTab else { return }
        settingsManager.setDisplayLiveTVTab(false)
    }

    /// Settings Plinx does not offer, pinned to the values its kid-facing
    /// screens assume, so a value persisted by an earlier build or a restored
    /// backup cannot switch them back on with no way for a parent to see it.
    static func resetHiddenSettings(_ settingsManager: SettingsManager) {
        if settingsManager.interface.homeHero != .off {
            settingsManager.setHomeHero(.off)
        }
        // Subtitle search writes to the server; it is a parent-only action.
        if settingsManager.playback.automaticSubtitleSearch {
            settingsManager.setAutomaticSubtitleSearch(false)
        }
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
