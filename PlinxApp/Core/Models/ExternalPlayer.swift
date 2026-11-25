import Foundation

// Plinx never hands playback to another app: that would bypass the content checks and the playback volume cap
// (docs/security/privacy-and-safety.md). Upstream's external-player feature is removed; what remains here is
//   - the persisted selection types, so `PlaybackSettings` still decodes settings saved by earlier builds, and
//   - the provider-level target, which `PlaybackService` still declares and `SafeMediaServices` disables.

/// A player upstream could hand playback to. Kept only to decode persisted settings.
nonisolated enum ExternalPlayerID: String, Codable, CaseIterable, Identifiable, Sendable {
    case infuse
    case vlc
    case iina
    case nativePlayer

    var id: String {
        rawValue
    }
}

/// A user-defined player upstream could hand playback to. Kept only to decode persisted settings.
nonisolated struct CustomExternalPlayer: Codable, Equatable, Sendable {
    var name: String
    var template: String
}

/// The external player choice persisted by upstream builds. Plinx clears it (`PlinxSettingsSanitizer`).
nonisolated enum ExternalPlayerSelection: Codable, Equatable, Hashable, Sendable {
    case known(ExternalPlayerID)
    case custom
}

nonisolated struct ExternalPlaybackTarget: Equatable, Sendable {
    let url: URL
    let title: String
    let item: MediaIdentity
    let duration: TimeInterval?
    var startPosition: TimeInterval = 0
    /// SRT files beside the video, best match first.
    var subtitles: [URL] = []
}

extension ExternalPlaybackTarget {
    init(url: URL, media: MediaItem) {
        self.init(url: url, title: Self.title(for: media), item: media.identity, duration: media.duration)
    }

    /// "Series — S01E02 — Title" for an episode, the item title otherwise.
    static func title(for media: MediaItem) -> String {
        guard media.type == .episode else { return media.title }
        var components: [String] = []
        if let series = media.grandparentTitle, !series.isEmpty {
            components.append(series)
        }
        if let season = media.parentIndex, let episode = media.index {
            components.append(String(format: "S%02dE%02d", season, episode))
        }
        components.append(media.title)
        return components.joined(separator: " — ")
    }
}

nonisolated enum ExternalPlaybackError: Error, Equatable {
    case noPlayableSource
}
