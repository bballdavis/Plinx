import Foundation
@testable import Plinx
import Testing

/// Plinx ships no Top Shelf extension; `TopShelfSessionStore.clear()` decodes what an earlier build may have stored
/// so it can remove it. Upstream's row merging and progress helpers served the extension and are gone.
@MainActor
struct TopShelfModelsTests {
    @Test func `v2 sessions list every server`() throws {
        // The shape upstream builds wrote, including fields Plinx no longer reads.
        let v2 = Data(#"""
        [
          {"provider":"plex","serverURL":"https://plex.example.invalid","serverID":"a"},
          {"provider":"jellyfin","serverURL":"https://jellyfin.example.invalid","serverID":"b","userID":"user"}
        ]
        """#.utf8)

        let decoded = TopShelfSessions.decode(v2: v2, v1: nil)

        #expect(decoded == [
            TopShelfStoredSession(provider: "plex", serverID: "a"),
            TopShelfStoredSession(provider: "jellyfin", serverID: "b"),
        ])
        #expect(decoded[1].tokenKey == "media.serverToken.jellyfin.b")
    }

    @Test func `the v1 session is found`() {
        let v1 = Data(#"{"provider":"plex","serverURL":"https://plex.example.invalid","serverID":"a"}"#.utf8)

        let decoded = TopShelfSessions.decode(v2: nil, v1: v1)

        #expect(decoded.map(\.serverID) == ["a"])
        #expect(decoded.map(\.tokenKey) == ["media.serverToken.plex.a"])
    }

    @Test func `v2 wins over a leftover v1 session`() throws {
        let v2 = try JSONEncoder().encode([TopShelfStoredSession(provider: "jellyfin", serverID: "b")])
        let v1 = Data(#"{"provider":"plex","serverURL":"https://plex.example.invalid","serverID":"a"}"#.utf8)

        #expect(TopShelfSessions.decode(v2: v2, v1: v1).map(\.serverID) == ["b"])
    }

    @Test func `unreadable or missing entries decode to nothing`() {
        #expect(TopShelfSessions.decode(v2: nil, v1: nil).isEmpty)
        #expect(TopShelfSessions.decode(v2: Data("not json".utf8), v1: Data("{}".utf8)).isEmpty)
    }
}
