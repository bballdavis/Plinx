public protocol PlexClient: Sendable {
    func fetchLibraries() async throws -> [PlexLibrary]
    func fetchItems(in library: PlexLibrary) async throws -> [PlinxMediaItem]
}

public struct PlexLibrary: Sendable, Equatable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public enum PlexClientError: Error, Sendable {
    case unavailable
}

public struct MockPlexClient: PlexClient {
    public init() {}

    public func fetchLibraries() async throws -> [PlexLibrary] {
        []
    }

    public func fetchItems(in library: PlexLibrary) async throws -> [PlinxMediaItem] {
        []
    }
}
