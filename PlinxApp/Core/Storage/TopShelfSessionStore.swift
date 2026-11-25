import Foundation

#if os(tvOS)
    /// Removes what an earlier build may have shared with a Top Shelf extension: the server list in the app group and
    /// the server tokens in the shared Keychain, in every format upstream used (v2 list, v1 single session, and the
    /// Plex-only keys before that).
    ///
    /// Plinx ships no Top Shelf extension and never writes these entries: server addresses and tokens stay inside the
    /// app. Only clearing remains, run by `PlinxSignOut` so a family that signs out leaves nothing behind. Earlier
    /// Plinx builds wrote only when the bundle declared `TopShelfKeychainAccessGroup`, which Plinx never did; the
    /// clear still covers that case.
    struct TopShelfSessionStore {
        private let defaults = UserDefaults(suiteName: TopShelfSessions.appGroup)

        private var keychain: Keychain? {
            guard let accessGroup = Bundle.main.object(forInfoDictionaryKey: "TopShelfKeychainAccessGroup") as? String,
                  !accessGroup.isEmpty
            else { return nil }
            return Keychain(service: TopShelfSessions.keychainService, accessGroup: accessGroup)
        }

        func clear() {
            if let keychain {
                for session in storedSessions() {
                    try? keychain.deleteValue(forKey: session.tokenKey)
                }
                try? keychain.deleteValue(forKey: TopShelfSessions.legacyTokenKey)
                try? keychain.deleteValue(forKey: TopShelfSessions.legacyPlexTokenKey)
            }
            defaults?.removeObject(forKey: TopShelfSessions.sessionsKey)
            defaults?.removeObject(forKey: TopShelfSessions.legacySessionKey)
            defaults?.removeObject(forKey: TopShelfSessions.legacyPlexURLKey)
        }

        private func storedSessions() -> [TopShelfStoredSession] {
            TopShelfSessions.decode(
                v2: defaults?.data(forKey: TopShelfSessions.sessionsKey),
                v1: defaults?.data(forKey: TopShelfSessions.legacySessionKey),
            ).sessions
        }
    }
#endif
