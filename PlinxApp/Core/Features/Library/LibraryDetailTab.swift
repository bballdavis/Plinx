import Foundation

enum LibraryDetailTab: String, CaseIterable, Codable, Hashable, Identifiable {
    case recommended
    case browse
    case collections
    case playlists

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .recommended:
            String(localized: "library.detail.tab.recommended")
        case .browse:
            String(localized: "library.detail.tab.browse")
        case .collections:
            String(localized: "library.detail.tab.collections")
        case .playlists:
            String(localized: "library.detail.tab.playlists")
        }
    }

    var systemImageName: String {
        switch self {
        case .recommended:
            "sparkles"
        case .browse:
            "square.grid.2x2.fill"
        case .collections:
            "rectangle.stack.fill"
        case .playlists:
            "music.note.list"
        }
    }

    static func available(
        for library: Library,
        provider: MediaProvider,
        displaysCollections: Bool,
        displaysPlaylists: Bool,
    ) -> [LibraryDetailTab] {
        if provider == .jellyfin {
            return library.type == .collection || library.type == .playlist
                ? [.browse]
                : [.recommended, .browse]
        }
        if library.isShared {
            return [.browse]
        }
        return allCases.filter { tab in
            switch tab {
            case .collections:
                displaysCollections
            case .playlists:
                displaysPlaylists
            default:
                true
            }
        }
    }

    static func defaultTab(for library: Library) -> LibraryDetailTab {
        library.isShared || library.type == .collection || library.type == .playlist ? .browse : .recommended
    }

    /// Falls back to the default when the saved tab has since been hidden in settings.
    static func resolved(
        saved: LibraryDetailTab?,
        available: [LibraryDetailTab],
        library: Library,
    ) -> LibraryDetailTab {
        if let saved, available.contains(saved) {
            return saved
        }
        return defaultTab(for: library)
    }
}
