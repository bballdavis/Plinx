import Foundation

struct PlinxLibraryViewSettings: Codable, Equatable {
    var hiddenRecommendSectionIds: [String] = []
    var recommendSectionOrder: [String] = []
}

@MainActor
extension SettingsManager {
    func libraryViewSettings(for libraryId: String) -> PlinxLibraryViewSettings {
        libraryViewSettingsStorage[libraryId] ?? PlinxLibraryViewSettings()
    }

    func setRecommendSectionHidden(_ hidden: Bool, libraryId: String, sectionId: String) {
        var entry = libraryViewSettings(for: libraryId)
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

    func setRecommendSectionOrder(_ sectionIds: [String], libraryId: String) {
        var entry = libraryViewSettings(for: libraryId)
        entry.recommendSectionOrder = sectionIds
        var all = libraryViewSettingsStorage
        all[libraryId] = entry
        libraryViewSettingsStorage = all
    }

    func resolvedRecommendSectionIds(for libraryId: String, availableSectionIds: [String]) -> [String] {
        let available = Set(availableSectionIds)
        let settings = libraryViewSettings(for: libraryId)
        return settings.recommendSectionOrder.filter { available.contains($0) }
    }

    private var libraryViewSettingsStorage: [String: PlinxLibraryViewSettings] {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: libraryViewStorageKey),
                let decoded = try? JSONDecoder().decode([String: PlinxLibraryViewSettings].self, from: data)
            else {
                return [:]
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: libraryViewStorageKey)
        }
    }
}

private let libraryViewStorageKey = "plinx.libraryViewSettings.v1"
