import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Seeded downloads for the `downloadsGrid` UI-test route (iOS only).
///
/// The fixtures are written as a pre-fork Plinx `index.json`, each entry
/// enrolled (`accessScope`) for a synthetic server and profile, so
/// `DownloadManager` imports them through its normal legacy migration with
/// that owner. `DownloadUITestHarness` then activates the owner as the current
/// profile's, which is what lets the grid show them: downloads stay
/// per-profile and fail closed even in UI tests. Ratings are G and TV-Y, so
/// the strictest default content policy allows them.
enum DownloadUITestFixtures {
    static let screenName = "downloadsGrid"

    /// The synthetic owner of every seeded download.
    static let owner = MediaOwner(
        server: ServerIdentity(provider: .plex, id: "plinx-ui-test-downloads"),
        userID: "ui-test-profile"
    )

    /// Replaces the downloads folder with the fixtures. Debug builds only, and
    /// only for a UI-test launch (`--ui-testing`) of the `downloadsGrid` route:
    /// it deletes whatever downloads the device holds.
    static func seedIfNeeded(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String]
    ) {
        #if DEBUG
        guard arguments.contains("--ui-testing"),
              environment["PLINX_UI_TEST_SCREEN"] == screenName
        else { return }
        seed(Int(environment["PLINX_UI_TEST_SEED"] ?? "") ?? 17)
        #endif
    }
}

#if DEBUG
extension DownloadUITestFixtures {
    private static func seed(_ seed: Int) {
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
                #if canImport(UIKit)
                try writePosterImage(for: item, to: folderURL)
                #endif
            }

            let indexURL = downloadsDirectory.appendingPathComponent("index.json", isDirectory: false)
            let entries = items.map { SeededIndexEntry(item: $0, accessScope: DownloadAccessScope(owner: owner)) }
            let data = try JSONEncoder().encode(entries)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            assertionFailure("Failed to seed downloads UI-test fixtures: \(error)")
        }
    }

    static func makeItems(seed: Int) -> [DownloadItem] {
        let totalCount = max(8, 8 + positiveModulo(seed, modulus: 5))
        let types: [MediaKind] = [.movie, .episode, .clip]
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        return (0 ..< totalCount).map { index in
            let type = types[index % types.count]
            let prefix: String = switch type {
            case .movie: "movie"
            case .episode: "tv"
            case .clip: "clip"
            default: "item"
            }
            let id = "\(prefix)-\(index)"
            let itemID = "rating-\(id)"
            let createdAt = baseDate.addingTimeInterval(TimeInterval(totalCount - index))

            let metadata = DownloadedMediaMetadata(
                identity: MediaIdentity(server: owner.server, itemID: itemID),
                guid: "guid-\(id)",
                type: type,
                title: title(for: type, index: index),
                summary: "Fixture \(index + 1)",
                genres: ["Family"],
                year: 2024,
                duration: type == .clip ? 95 : 3_600,
                viewCount: nil,
                contentRating: type == .movie ? "G" : "TV-Y",
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
                requestedQuality: .original,
                effectiveQuality: .original,
                audioTitle: nil,
                subtitleTitle: nil,
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
                metadata: metadata,
                ownerID: owner.id
            )
        }
    }

    private static func title(for type: MediaKind, index: Int) -> String {
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
            // Every other clip gets portrait art, like a home video with a
            // badly cached poster: the grid must still draw it landscape.
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

    private static func posterColor(for type: MediaKind) -> UIColor {
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

/// One entry of the seeded `index.json`: the download plus the enrollment
/// scope pre-fork Plinx stored beside it, which `DownloadManager`'s legacy
/// migration turns into the download's owner.
private struct SeededIndexEntry: Encodable {
    let item: DownloadItem
    let accessScope: DownloadAccessScope

    private enum CodingKeys: String, CodingKey {
        case accessScope
    }

    func encode(to encoder: Encoder) throws {
        try item.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessScope, forKey: .accessScope)
    }
}
#endif

/// The `downloadsGrid` UI-test route: the downloads grid with the fixture
/// owner active, as if its profile were signed in. Re-applied whenever the
/// active owners change (for example when a saved session connects), so the
/// seeded downloads stay visible for the test.
struct DownloadUITestHarness: View {
    @Environment(DownloadManager.self) private var downloadManager

    private var isFixtureOwnerActive: Bool {
        downloadManager.activeOwnerIDs.contains(DownloadUITestFixtures.owner.id)
    }

    var body: some View {
        PlinxDownloadsGridView()
            .task(id: isFixtureOwnerActive) {
                guard !isFixtureOwnerActive else { return }
                downloadManager.activateOwners([DownloadUITestFixtures.owner])
            }
    }
}
