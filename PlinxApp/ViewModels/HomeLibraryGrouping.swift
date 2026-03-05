// ─────────────────────────────────────────────────────────────────────────────
// HomeLibraryGrouping.swift — Testable home-screen categorisation logic
// ─────────────────────────────────────────────────────────────────────────────
//
// Extracted from PlinxHomeView so the hub→library matching algorithm can be
// verified by the app unit-test target without spinning up a simulator UI.
//
// Key rules:
//   1. Section-ID match first (most reliable — Plex embeds the section key
//      in the hub identifier, e.g. "hub.home.recentlyadded.3").
//   2. Title-based match next (strip the "Recently Added" prefix then compare).
//   3. Type-keyword match last — clip libraries require an explicit
//      "clip/video/home" signal so they can NEVER be merged into the
//      combined movies+TV row through a false-positive ID match.
// ─────────────────────────────────────────────────────────────────────────────

enum HomeLibraryGrouping {

    // MARK: - Public matching interface

    /// Match a recently-added `Hub` to the best-fitting `Library` in the store.
    ///
    /// - Parameters:
    ///   - hub: A recently-added hub from the Plex API.
    ///   - libraries: All available library sections from `LibraryStore`.
    ///   - recentlyAddedPrefix: Localised "Recently Added" prefix to strip from
    ///     hub titles before title matching (e.g. "Recently Added ").
    /// - Returns: The closest matching `Library`, or `nil` if none can be
    ///   identified. `nil` entries are treated as non-movie/non-show in the
    ///   home-screen grouping logic.
    static func matchLibrary(
        for hub: Hub,
        in libraries: [Library],
        recentlyAddedPrefix: String
    ) -> Library? {
        let hubId = hub.id.lowercased()

        // ── Priority 1: Section-ID matching ────────────────────────────────
        // Plex hub identifiers often embed the section key, e.g.:
        //   "hub.home.recentlyadded.3"   →  sectionId 3
        //   "hub.home.recentlyadded.3::movie"
        // The ".<N>" delimiter prevents single-digit IDs from false-matching
        // inside longer numeric strings (e.g. sectionId=1 must not match "11").
        for lib in libraries {
            if let sectionId = lib.sectionId {
                let token = ".\(sectionId)"
                if hubId.hasSuffix(token)
                    || hubId.contains("\(token)::")
                    || hubId.contains("\(token).") {
                    return lib
                }
            }
        }

        // ── Priority 2: Title-based matching ───────────────────────────────
        let title = hub.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            let stripped = title
                .replacingOccurrences(of: recentlyAddedPrefix, with: "",
                                      options: [.caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty {
                // Exact case-insensitive + diacritic-insensitive match.
                if let exact = libraries.first(where: {
                    $0.title.compare(stripped,
                                     options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }) {
                    return exact
                }
                // Contains match (handles e.g. "Home Videos" ↔ "Home Videos Library").
                if let contains = libraries.first(where: {
                    stripped.localizedCaseInsensitiveContains($0.title)
                        || $0.title.localizedCaseInsensitiveContains(stripped)
                }) {
                    return contains
                }
            }
        }

        // ── Priority 3: Type-keyword matching ──────────────────────────────
        // Only fires when the hub identifier contains an unambiguous type token.
        // Clip libraries require an EXPLICIT clip/video/home signal so they are
        // never accidentally merged into the movies+TV combined row.
        return libraries.first { lib in
            switch lib.type {
            case .movie: return hubId.contains("movie") || hubId.contains("film")
            case .show:  return hubId.contains("show") || hubId.contains("tv") || hubId.contains("series")
            case .clip:  return hubId.contains("clip") || hubId.contains("video")
            default:     return false
            }
        }
    }

    /// Heuristic fallback used when library metadata is unavailable at filter time.
    /// This keeps known Other Video hubs (YouTube/Home Videos/clip-style) visible
    /// instead of dropping them under strict unrated filtering.
    static func isLikelyOtherVideoHub(_ hub: Hub, recentlyAddedPrefix: String) -> Bool {
        let hubId = hub.id.lowercased()
        let rawTitle = hub.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedTitle = rawTitle
            .replacingOccurrences(of: recentlyAddedPrefix, with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let idHints = ["youtube", "homevideo", "home-video", "othervideo", "other-video", "::clip", ".clip", ".videos"]
        let titleHints = ["youtube", "home video", "home videos", "other video", "other videos", "clips", "videos"]

        if idHints.contains(where: { hubId.contains($0) }) {
            return true
        }
        return titleHints.contains(where: { strippedTitle.contains($0) })
    }

    // MARK: - Grouping helpers

    /// Returns `true` if a recently-added hub entry belongs in the combined
    /// movies+TV row (type is `.movie` or `.show` AND is managed by a real agent).
    static func isMoviesOrTV(_ library: Library?) -> Bool {
        guard let lib = library else { return false }
        // "none" agent libraries (e.g. YouTube, Home Videos) are NOT movies/TV
        // even if their Plex section type is declared as "movie".
        if isNoneAgentLibrary(lib) { return false }
        return lib.type == .movie || lib.type == .show
    }

    /// Returns `true` if a recently-added hub entry belongs in the
    /// "Other Videos" rows (any type that is not movie or show, OR a none-agent library).
    static func isOtherVideo(_ library: Library?) -> Bool {
        guard let lib = library else { return true }   // unmatched → treat as other
        if isNoneAgentLibrary(lib) { return true }     // none-agent (YouTube, etc.) → other
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
