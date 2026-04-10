import Foundation

#if canImport(UIKit)
import UIKit
#endif

public enum DownloadUITestFixtures {
    public static let screenName = "downloadsGrid"

    public static func seedIfNeeded(environment: [String: String]) {
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

    public static func makeItems(seed: Int) -> [DownloadUITestItem] {
        let totalCount = max(8, 8 + positiveModulo(seed, modulus: 5))
        let types: [DownloadUITestItemType] = [.movie, .episode, .clip]
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        return (0..<totalCount).map { index in
            let type = types[index % types.count]
            let prefix: String = switch type {
            case .movie: "movie"
            case .episode: "tv"
            case .clip: "clip"
            }
            let id = "\(prefix)-\(index)"
            let createdAt = baseDate.addingTimeInterval(TimeInterval(totalCount - index))

            let metadata = DownloadUITestMetadata(
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
                createdAt: createdAt,
                resolvedArtworkLayoutStyle: resolveArtworkLayout(for: type),
                isPortraitArtwork: type == .clip && fixtureIndex(for: id).isMultiple(of: 2)
            )

            return DownloadUITestItem(
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

    public static func buildDownloadsDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return appSupport.appendingPathComponent("Downloads", isDirectory: true)
    }

    #if canImport(UIKit)
    public static func writePosterImage(for item: DownloadUITestItem, to folderURL: URL) throws {
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

    private static func posterSize(for item: DownloadUITestItem) -> CGSize {
        if item.metadata.type == .clip {
            if item.metadata.isPortraitArtwork {
                return CGSize(width: 480, height: 720)
            }
            return CGSize(width: 720, height: 405)
        }

        if item.metadata.isPortraitArtwork {
            return CGSize(width: 480, height: 720)
        }

        return CGSize(width: 720, height: 405)
    }

    private static func posterColor(for type: DownloadUITestItemType) -> UIColor {
        switch type {
        case .movie:
            return .systemBlue
        case .episode:
            return .systemGreen
        case .clip:
            return .systemOrange
        }
    }
    #endif

    private static func title(for type: DownloadUITestItemType, index: Int) -> String {
        switch type {
        case .movie:
            return "Movie \(index + 1)"
        case .episode:
            return "Episode \(index + 1)"
        case .clip:
            return "Other Video \(index + 1)"
        }
    }

    private static func positiveModulo(_ value: Int, modulus: Int) -> Int {
        ((value % modulus) + modulus) % modulus
    }

    private static func fixtureIndex(for id: String) -> Int {
        guard let suffix = id.split(separator: "-").last, let value = Int(suffix) else {
            return 0
        }
        return value
    }

    private static func resolveArtworkLayout(for type: DownloadUITestItemType) -> String {
        switch type {
        case .movie:
            return "posterArt"
        case .episode:
            return "posterArt"
        case .clip:
            return "squareArt"
        }
    }
}

// MARK: - Public Test Types
public enum DownloadUITestItemType: Codable, Hashable {
    case movie, episode, clip
}

public struct DownloadUITestItem: Codable, Hashable {
    public let id: String
    public let status: DownloadUITestStatus
    public let progress: Double
    public let bytesWritten: Int64
    public let totalBytes: Int64
    public let taskIdentifier: Int?
    public let errorMessage: String?
    public let metadata: DownloadUITestMetadata

    public init(id: String, status: DownloadUITestStatus, progress: Double, bytesWritten: Int64, totalBytes: Int64, taskIdentifier: Int?, errorMessage: String?, metadata: DownloadUITestMetadata) {
        self.id = id
        self.status = status
        self.progress = progress
        self.bytesWritten = bytesWritten
        self.totalBytes = totalBytes
        self.taskIdentifier = taskIdentifier
        self.errorMessage = errorMessage
        self.metadata = metadata
    }
}

public enum DownloadUITestStatus: String, Codable, Hashable {
    case downloading, completed, failed, paused
}

public struct DownloadUITestMetadata: Codable, Hashable {
    public let ratingKey: String
    public let guid: String
    public let type: DownloadUITestItemType
    public let title: String
    public let summary: String
    public let genres: [String]
    public let year: Int
    public let duration: Int
    public let contentRating: String
    public let studio: String
    public let tagline: String?
    public let parentRatingKey: String?
    public let grandparentRatingKey: String?
    public let grandparentTitle: String?
    public let parentTitle: String?
    public let parentIndex: Int?
    public let index: Int?
    public let posterFileName: String
    public let videoFileName: String
    public let fileSize: Int
    public let createdAt: Date
    public let resolvedArtworkLayoutStyle: String
    public let isPortraitArtwork: Bool

    public init(ratingKey: String, guid: String, type: DownloadUITestItemType, title: String, summary: String, genres: [String], year: Int, duration: Int, contentRating: String, studio: String, tagline: String?, parentRatingKey: String?, grandparentRatingKey: String?, grandparentTitle: String?, parentTitle: String?, parentIndex: Int?, index: Int?, posterFileName: String, videoFileName: String, fileSize: Int, createdAt: Date, resolvedArtworkLayoutStyle: String, isPortraitArtwork: Bool) {
        self.ratingKey = ratingKey
        self.guid = guid
        self.type = type
        self.title = title
        self.summary = summary
        self.genres = genres
        self.year = year
        self.duration = duration
        self.contentRating = contentRating
        self.studio = studio
        self.tagline = tagline
        self.parentRatingKey = parentRatingKey
        self.grandparentRatingKey = grandparentRatingKey
        self.grandparentTitle = grandparentTitle
        self.parentTitle = parentTitle
        self.parentIndex = parentIndex
        self.index = index
        self.posterFileName = posterFileName
        self.videoFileName = videoFileName
        self.fileSize = fileSize
        self.createdAt = createdAt
        self.resolvedArtworkLayoutStyle = resolvedArtworkLayoutStyle
        self.isPortraitArtwork = isPortraitArtwork
    }
}
