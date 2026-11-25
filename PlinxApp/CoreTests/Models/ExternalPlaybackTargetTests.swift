import Foundation
@testable import Plinx
import Testing

/// Plinx never launches an external player; the provider-level target stays because `PlaybackService` declares it
/// (and `SafeMediaServices` disables it). Upstream's launch requests, URL templates and callbacks are removed.
@MainActor
struct ExternalPlaybackTargetTests {
    @Test func `episode title includes the series and episode number`() {
        let server = ServerIdentity(provider: .plex, id: "server-1")
        let episode = MediaItem.make(
            id: "1",
            server: server,
            title: "Pilot",
            type: .episode,
            seasonNumber: 1,
            episodeNumber: 2,
            seriesTitle: "Show",
        )
        let movie = MediaItem.make(id: "2", server: server, title: "Movie")

        #expect(ExternalPlaybackTarget.title(for: episode) == "Show — S01E02 — Pilot")
        #expect(ExternalPlaybackTarget.title(for: movie) == "Movie")
    }
}
