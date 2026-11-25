import AetherEngine
import Foundation
@testable import Plinx
import Testing

/// Sidecar subtitle files as Plinx's own player and the downloads read them.
@MainActor
struct PlexSidecarSubtitleTests {
    private let baseURL = URL(string: "https://plex.example.com:32400")!

    @Test func `ties player sidecars to their Plex stream ids`() throws {
        let container = try Fixtures.decode(PlexItemMediaContainer.self, from: "plex-movie-versions")
        let item = try #require(container.mediaContainer.metadata?.first)
        let streams = try #require(item.media?.first?.parts.first?.stream)
        let subtitles = PlexMediaServiceAdapter.externalSubtitles(in: streams) {
            MediaRepository.mediaURL(path: $0, baseURL: baseURL, token: "test-token")
        }

        #expect(subtitles.map(\.providerStreamID) == [403, 404, 405])
        #expect(subtitles.map(\.track.url.absoluteString) == [
            "https://plex.example.com:32400/library/streams/403?X-Plex-Token=test-token",
            "https://plex.example.com:32400/library/streams/404?X-Plex-Token=test-token",
            "https://plex.example.com:32400/library/streams/405?X-Plex-Token=test-token",
        ])
    }

    @Test func `downloads every external subtitle file next to the video`() throws {
        let container = try Fixtures.decode(PlexItemMediaContainer.self, from: "plex-movie-versions")
        let item = try #require(container.mediaContainer.metadata?.first)
        let streams = try #require(item.media?.first?.parts.first?.stream)
        let sidecars = PlexMediaServiceAdapter.downloadSidecars(in: streams) {
            MediaRepository.mediaURL(path: $0, baseURL: baseURL, token: "test-token")
        }

        #expect(sidecars.map(\.request.url?.absoluteString) == [
            "https://plex.example.com:32400/library/streams/403?X-Plex-Token=test-token",
            "https://plex.example.com:32400/library/streams/404?X-Plex-Token=test-token",
            "https://plex.example.com:32400/library/streams/405?X-Plex-Token=test-token",
        ])
        #expect(sidecars.map(\.fileExtension) == ["srt", "srt", "ass"])
        #expect(sidecars.map(\.language) == ["English", "French", "German"])
    }
}
