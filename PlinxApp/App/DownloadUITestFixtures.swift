import Foundation

#if canImport(UIKit)
import UIKit
#endif

enum DownloadUITestFixtures {
    static let screenName = "downloadsGrid"

    static func seedIfNeeded(environment: [String: String]) {
        guard environment["PLINX_UI_TEST_SCREEN"] == screenName else { return }

        let seed = Int(environment["PLINX_UI_TEST_SEED"] ?? "") ?? 17
        let downloadsDirectory = buildDownloadsDirectory()

        do {
            if FileManager.default.fileExists(atPath: downloadsDirectory.path) {
                try FileManager.default.removeItem(at: downloadsDirectory)
            }
            try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)

            let items = makeItems(seed: seed)
            for item in items {
                let folderURL = downloadsDirectory.appendingPathComponent(item.id, isDirectory: true)
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                try writePosterImage(for: item, to: folderURL)
            }

            let indexURL = downloadsDirectory.appendingPathComponent("index.json", isDirectory: false)
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            assertionFailure("Failed to seed downloads UI-test fixtures: \(error)")
        }
    }

    static func makeItems(seed: Int) -> [DownloadItem] {
        let totalCount = max(8, 8 + positiveModulo(seed, modulus: 5))
        let types: [PlexItemType] = [.movie, .episode, .clip]
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        return (0..<totalCount).map { index in
            let type = types[index % types.count]
            let prefix: String = switch type {
            case .movie: "movie"
            case .episode: "tv"
            case .clip: "clip"
            default: "item"
            }
            let id = "\(prefix)-\(index)"
            let createdAt = baseDate.addingTimeInterval(TimeInterval(totalCount - index))

            let metadata = DownloadedMediaMetadata(
                ratingKey: "rating-\(id)",
                guid: "guid-\(id)",
                type: type,
                title: title(for: type, index: index),
                summary: "Fixture \(index + 1)",
                genres: ["Family"],
                year: 2024,
                duration: type == .clip ? 95 : 3_600,
                contentRating: type == .movie ? "PG" : "TV-PG",
                studio: "Plinx Fixtures",
                tagline: nil,
                parentRatingKey: type == .episode ? "season-\(index)" : nil,
                grandparentRatingKey: type == .episode ? "show-\(index)" : nil,
                grandparentTitle: type == .episode ? "Show \(index + 1)" : nil,
                parentTitle: type == .episode ? "Season 1" : nil,
                parentIndex: type == .episode ? 1 : nil,
                index: type == .episode ? (index + 1) : nil,
                posterFileName: "poster.jpg",
                videoFileName: "video.mp4",
                fileSize: 1_000_000,
                createdAt: createdAt
            )

            return DownloadItem(
                id: id,
                status: .downloading,
                progress: 0.15 + (Double(index % 5) * 0.15),
                bytesWritten: Int64(150_000 + index * 10_000),
                totalBytes: 1_000_000,
                taskIdentifier: nil,
                errorMessage: nil,
                metadata: metadata
            )
        }
    }

    private static func title(for type: PlexItemType, index: Int) -> String {
        switch type {
        case .movie:
            return "Movie \(index + 1)"
        case .episode:
            return "Episode \(index + 1)"
        case .clip:
            return "Other Video \(index + 1)"
        default:
            return "Download \(index + 1)"
        }
    }

    private static func positiveModulo(_ value: Int, modulus: Int) -> Int {
        ((value % modulus) + modulus) % modulus
    }

    static func buildDownloadsDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return appSupport.appendingPathComponent("Downloads", isDirectory: true)
    }

    #if canImport(UIKit)
    static func writePosterImage(for item: DownloadItem, to folderURL: URL) throws {
        let size = posterSize(for: item)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let bounds = CGRect(origin: .zero, size: size)
            posterColor(for: item.metadata.type).setFill()
            context.fill(bounds)

            let stripeRect = CGRect(x: 0, y: size.height * 0.72, width: size.width, height: size.height * 0.28)
            UIColor.black.withAlphaComponent(0.32).setFill()
            context.fill(stripeRect)
        }

        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let destination = folderURL.appendingPathComponent("poster.jpg", isDirectory: false)
        try data.write(to: destination, options: .atomic)
    }

    private static func posterSize(for item: DownloadItem) -> CGSize {
        if item.metadata.type == .clip {
            let forcedPortraitClip = fixtureIndex(for: item.id).isMultiple(of: 2)
            if forcedPortraitClip {
                return CGSize(width: 480, height: 720)
            }
            return CGSize(width: 720, height: 405)
        }

        if DownloadsArtworkLayoutPolicy.isPortraitArtworkType(item.metadata.resolvedArtworkLayoutStyle) {
            return CGSize(width: 480, height: 720)
        }

        return CGSize(width: 720, height: 405)
    }

    private static func posterColor(for type: PlexItemType) -> UIColor {
        switch type {
        case .movie:
            return .systemBlue
        case .episode:
            return .systemGreen
        case .clip:
            return .systemOrange
        default:
            return .systemGray
        }
    }

    private static func fixtureIndex(for id: String) -> Int {
        guard let suffix = id.split(separator: "-").last, let value = Int(suffix) else {
            return 0
        }
        return value
    }
    #endif
}