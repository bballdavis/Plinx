#if canImport(MPVKit)
import MPVKit
#endif

public struct MPVKitPlaybackEngine: PlaybackEngine {
    public init() {}

    public func load(id: String) async throws {
        #if canImport(MPVKit)
        // Wire MPVKit player to a Plex media URL when available.
        #else
        throw PlaybackEngineError.unavailable
        #endif
    }

    public func play() async {
        #if canImport(MPVKit)
        // play
        #endif
    }

    public func pause() async {
        #if canImport(MPVKit)
        // pause
        #endif
    }

    public func stop() async {
        #if canImport(MPVKit)
        // stop
        #endif
    }
}
