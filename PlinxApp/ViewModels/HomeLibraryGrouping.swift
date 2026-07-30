// Home row categorisation based on canonical Plex library metadata.
//
// Recently-added rows are keyed by `LibraryCatalogResult`, so this type does
// not infer library identity from promoted-hub identifiers or localized titles.

enum HomeLibraryGrouping {

    struct ContinueWatchingRow: Identifiable, Equatable {
        let id: String
        let title: String
        let sectionKey: String
        let items: [MediaDisplayItem]
    }

    static func continueWatchingRows(from hub: Hub?) -> [ContinueWatchingRow] {
        guard let hub, hub.hasItems else { return [] }
        return [
            ContinueWatchingRow(
                id: hub.id,
                title: hub.title,
                sectionKey: "continueWatching",
                items: hub.items
            )
        ]
    }

    /// Standard movie and TV agent libraries can participate in combined rows.
    static func isMoviesOrTV(_ library: Library?) -> Bool {
        guard let lib = library else { return false }
        // "none" agent libraries (e.g. YouTube, Home Videos) are NOT movies/TV
        // even if their Plex section type is declared as "movie".
        if isNoneAgentLibrary(lib) { return false }
        return lib.type == .movie || lib.type == .show
    }

    /// None-agent and non-movie/show libraries remain separate Other Videos rows.
    static func isOtherVideo(_ library: Library?) -> Bool {
        guard let lib = library else { return false }
        if isNoneAgentLibrary(lib) { return true }
        return lib.type != .movie && lib.type != .show
    }

    /// Compatibility shim for vendor patch drift.
    ///
    /// Delegates to `Library.isNoneAgentLibrary` which reads the Plex agent
    /// string (e.g. "tv.plex.agents.none" for YouTube / Home Videos libs).
    private static func isNoneAgentLibrary(_ library: Library) -> Bool {
        library.isNoneAgentLibrary
    }
}
