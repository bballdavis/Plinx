import Foundation

struct PlinxLibraryViewSettings: Codable, Equatable {
    var hiddenRecommendSectionIds: [String] = []
    var recommendSectionOrder: [String] = []
}

@MainActor
extension SettingsManager {
    func plinxLibraryViewSettings(for libraryId: String) -> PlinxLibraryViewSettings {
        libraryViewSettingsStorage[libraryId] ?? PlinxLibraryViewSettings()
    }

    func plinxSetRecommendSectionHidden(_ hidden: Bool, libraryId: String, sectionId: String) {
        var entry = plinxLibraryViewSettings(for: libraryId)
        var hiddenSet = Set(entry.hiddenRecommendSectionIds)
        if hidden {
            hiddenSet.insert(sectionId)
        } else {
            hiddenSet.remove(sectionId)
        }
        entry.hiddenRecommendSectionIds = hiddenSet.sorted()
        var all = libraryViewSettingsStorage
        all[libraryId] = entry
        libraryViewSettingsStorage = all
    }

    func plinxSetRecommendSectionOrder(_ sectionIds: [String], libraryId: String) {
        var entry = plinxLibraryViewSettings(for: libraryId)
        entry.recommendSectionOrder = sectionIds
        var all = libraryViewSettingsStorage
        all[libraryId] = entry
        libraryViewSettingsStorage = all
    }

    func plinxResolvedRecommendSectionIds(for libraryId: String, availableSectionIds: [String]) -> [String] {
        let available = Set(availableSectionIds)
        let settings = plinxLibraryViewSettings(for: libraryId)
        return settings.recommendSectionOrder.filter { available.contains($0) }
    }

    private var libraryViewSettingsStorage: [String: PlinxLibraryViewSettings] {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: plinxLibraryViewStorageKey),
                let decoded = try? JSONDecoder().decode([String: PlinxLibraryViewSettings].self, from: data)
            else {
                return [:]
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: plinxLibraryViewStorageKey)
        }
    }
}

/// UserDefaults key for per-library view settings; also the iCloud sync name.
let plinxLibraryViewStorageKey = "plinx.libraryViewSettings.v1"