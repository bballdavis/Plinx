public protocol PlaybackEngine: Sendable {
    func load(id: String) async throws
    func play() async
    func pause() async
    func stop() async
}

public enum PlaybackEngineError: Error, Sendable {
    case unavailable
}
