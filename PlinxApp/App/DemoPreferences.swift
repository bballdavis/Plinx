import Foundation
import PlinxCore

/// Sample settings and PIN never change the family's preferences or PIN.
@MainActor
enum DemoPreferences {
    static let defaults = UserDefaults(suiteName: "com.bballdavis.plinx.demo")!
    private static let credentials = DemoYoutarrCredentials()
    static var youtarrStore: YoutarrConfigurationStore {
        YoutarrConfigurationStore(defaults: defaults, credentials: credentials)
    }
    static func configureYoutarr(baseURL: URL) {
        _ = try? youtarrStore.save(baseURL: baseURL.absoluteString, apiKey: "plinx-sample-api-key")
    }

    static private(set) var settings = SettingsManager(userDefaults: defaults)
    static private(set) var parentalAccess = ParentalAccessCoordinator(store: DemoPINStore(), legacyDefaults: defaults)

    static func reset() {
        defaults.removePersistentDomain(forName: "com.bballdavis.plinx.demo")
        defaults.set(PlinxRating.pg.rawValue, forKey: "plinx.maxMovieRating")
        defaults.set(PlinxRating.tvPg.rawValue, forKey: "plinx.maxTVRating")
        defaults.set(true, forKey: "plinx.excludeUnrated")
        settings = SettingsManager(userDefaults: defaults)
        settings.setDisplayCollections(true)
        settings.setDisplayPlaylists(true)
        defaults.set(true, forKey: YoutarrExplorePreference.storageKey)
        parentalAccess = ParentalAccessCoordinator(store: DemoPINStore(), legacyDefaults: defaults)
    }
}

private final class DemoPINStore: ParentalPINStoring {
    private var pin: String? = "2468"
    func readPIN() throws -> String? { pin }
    func writePIN(_ pin: String) throws { self.pin = pin }
    func deletePIN() throws { pin = nil }
}

private final class DemoYoutarrCredentials: YoutarrCredentialStoring {
    private var values: [String: String] = [:]
    func string(forKey key: String) throws -> String? { values[key] }
    func setString(_ value: String, forKey key: String) throws { values[key] = value }
    func deleteValue(forKey key: String) throws { values[key] = nil }
}
