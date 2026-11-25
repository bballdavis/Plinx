// Home row categorisation based on canonical library metadata.
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

    /// One Continue Watching row from the home's watching rows, merged across
    /// servers by `HomeViewModel`. Next Up (Jellyfin servers that keep it
    /// apart) joins the end of the same row, so kids find everything they
    /// started in one place.
    static func continueWatchingRows(from rows: [HomeRow]) -> [ContinueWatchingRow] {
        let continueRows = rows.filter { $0.kind == .continueWatching }
        let nextUpRows = rows.filter { $0.kind == .nextUp }
        guard let first = continueRows.first ?? nextUpRows.first else { return [] }
        var seen: Set<String> = []
        let items = (continueRows + nextUpRows)
            .flatMap(\.items)
            .filter { seen.insert(itemKey($0)).inserted }
        return continueWatchingRows(from: Hub(id: first.id, title: first.title, items: items))
    }

    /// Identifies an item across servers: rating keys and Jellyfin ids repeat
    /// from one server to the next.
    static func itemKey(_ item: MediaDisplayItem) -> String {
        "\(item.server.stableKey)|\(item.id)"
    }

    /// Standard movie and TV agent libraries can participate in combined rows.
    static func isMoviesOrTV(_ library: Library?) -> Bool {
        guard let lib = library else { return false }
        // "none" agent libraries (e.g. YouTube, Home Videos) are NOT movies/TV
        // even if their Plex section type is declared as "movie".
        if isNoneAgentLibrary(lib) { return false }
        return lib.type == .movie || lib.type == .series
    }

    /// None-agent and non-movie/series libraries remain separate Other Videos rows.
    static func isOtherVideo(_ library: Library?) -> Bool {
        guard let lib = library else { return false }
        if isNoneAgentLibrary(lib) { return true }
        return lib.type != .movie && lib.type != .series
    }

    /// Delegates to `Library.isNoneAgentLibrary`, which reads the Plex agent
    /// string (e.g. "tv.plex.agents.none" for YouTube / Home Videos libraries).
    private static func isNoneAgentLibrary(_ library: Library) -> Bool {
        library.isNoneAgentLibrary
    }
}
