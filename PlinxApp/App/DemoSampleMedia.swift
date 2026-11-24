import Foundation

enum DemoSampleMedia {
    static let durationMilliseconds = 90_000

    static func url(isEpisode: Bool) -> URL? {
        Bundle.main.url(forResource: isEpisode ? "episode" : "movie", withExtension: "mp4", subdirectory: "DemoMedia")
    }

    static func data(isEpisode: Bool) -> Data? {
        guard let url = url(isEpisode: isEpisode) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    static func byteCount(isEpisode: Bool) -> Int {
        data(isEpisode: isEpisode)?.count ?? 0
    }

    static var isAvailable: Bool {
        byteCount(isEpisode: false) > 0 && byteCount(isEpisode: true) > 0
    }
}
