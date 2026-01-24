public final class MockPlexServer: Sendable {
    public struct Library: Sendable, Equatable {
        public let id: String
        public let title: String
        public let items: [PlinxMediaItem]
    }

    public init() {}

    public func loadLibraries() -> [Library] {
        []
    }
}
