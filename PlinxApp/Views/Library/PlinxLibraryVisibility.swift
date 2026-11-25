import Foundation

/// Which libraries a profile shows: Plinx's "Visible Libraries" setting, stored
/// as upstream's per-profile `LibraryPreferences.hiddenLibraries`.
///
/// A hidden library is left out of the Library tab, Home (upstream passes the
/// hidden libraries to every home request) and search. Hiding a library is a
/// parent's curation, not the rating policy: `ContentSafetyGate` still judges
/// every title that a visible library returns.
@MainActor
enum PlinxLibraryVisibility {
    /// The active profile's hidden libraries.
    static func hiddenLibraries(
        settingsManager: SettingsManager,
        sessionManager: SessionManager,
    ) -> Set<LibraryIdentity> {
        hiddenLibraries(settingsManager: settingsManager, profileID: sessionManager.activeProfile?.id ?? "")
    }

    static func hiddenLibraries(settingsManager: SettingsManager, profileID: String) -> Set<LibraryIdentity> {
        Set(settingsManager.libraryPreferences(profileID: profileID).hiddenLibraries)
    }

    /// Libraries offered on the kid-facing Library tab: the profile's visible
    /// libraries, without playlist libraries (playlists have no Plinx surface).
    static func browsableLibraries(_ libraries: [Library]) -> [Library] {
        libraries.filter { $0.type != .playlist }
    }

    /// Whether a search result from `server` may be listed.
    ///
    /// A result that names its library is hidden exactly when that library is
    /// hidden. A result that does not name one (Jellyfin results, Plex items
    /// shared one by one) cannot be matched, so it fails closed: it is hidden
    /// while the profile hides any library of that server.
    static func isVisible(
        _ media: MediaDisplayItem,
        on server: ServerIdentity,
        hiddenLibraries: Set<LibraryIdentity>,
    ) -> Bool {
        guard !hiddenLibraries.isEmpty else { return true }
        if let libraryID = media.playableItem?.librarySectionID {
            return !hiddenLibraries.contains(LibraryIdentity(server: server, libraryID: libraryID))
        }
        return !hiddenLibraries.contains { $0.server == server }
    }

    static func visibleSources(
        _ sources: [SearchResultSource],
        hiddenLibraries: Set<LibraryIdentity>,
    ) -> [SearchResultSource] {
        sources.filter { isVisible($0.media, on: $0.server, hiddenLibraries: hiddenLibraries) }
    }
}
