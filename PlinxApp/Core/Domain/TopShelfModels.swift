import Foundation

// Where upstream builds shared servers with a Top Shelf extension. Plinx ships no extension and never writes these
// entries; `TopShelfSessionStore.clear()` uses this file to find and remove anything an earlier build left behind.

/// A server entry an earlier build stored for a Top Shelf extension. Its token lives in the shared Keychain under
/// `tokenKey`.
nonisolated struct TopShelfStoredSession: Codable, Hashable, Sendable {
    let provider: String
    let serverID: String

    var tokenKey: String {
        "media.serverToken.\(provider).\(serverID)"
    }
}

nonisolated enum TopShelfSessions {
    static let appGroup = "group.com.github.wunax.strimr"
    static let keychainService = "com.github.wunax.strimr.top-shelf"
    static let sessionsKey = "media.session.v2"
    static let legacySessionKey = "media.session.v1"
    static let legacyTokenKey = "media.serverToken"
    // Plex-only format that predates v1.
    static let legacyPlexTokenKey = "plex.serverToken"
    static let legacyPlexURLKey = "plex.serverURL"

    /// Stored sessions: the v2 list, or else the single v1 session of the version before it.
    static func decode(v2: Data?, v1: Data?) -> [TopShelfStoredSession] {
        if let v2, let sessions = try? JSONDecoder().decode([TopShelfStoredSession].self, from: v2) {
            return sessions
        }
        guard let v1, let session = try? JSONDecoder().decode(TopShelfStoredSession.self, from: v1) else {
            return []
        }
        return [session]
    }
}
