import XCTest
@testable import Plinx

final class QuickActionDownloadActionPolicyTests: XCTestCase {
    private let server = ServerIdentity(provider: .plex, id: "server-1")

    func test_movieWithoutDownloadShowsDownloadAction() {
        let media = makeMediaItem(id: "movie-1", type: .movie)

        let action = QuickActionDownloadActionPolicy.action(for: media, downloadItems: [])

        XCTAssertEqual(action, .download)
    }

    func test_completedMovieShowsGoToDownloadsAction() {
        let media = makeMediaItem(id: "movie-1", type: .movie)
        let downloads = [makeDownloadItem(itemID: "movie-1", type: .movie, status: .completed)]

        let action = QuickActionDownloadActionPolicy.action(for: media, downloadItems: downloads)

        XCTAssertEqual(action, .goToDownloads)
    }

    func test_failedMovieStillShowsDownloadAction() {
        let media = makeMediaItem(id: "movie-1", type: .movie)
        let downloads = [makeDownloadItem(itemID: "movie-1", type: .movie, status: .failed)]

        let action = QuickActionDownloadActionPolicy.action(for: media, downloadItems: downloads)

        XCTAssertEqual(action, .download)
    }

    func test_downloadFromAnotherServerDoesNotHideDownloadAction() {
        let media = makeMediaItem(id: "movie-1", type: .movie)
        let downloads = [
            makeDownloadItem(
                itemID: "movie-1",
                type: .movie,
                status: .completed,
                server: ServerIdentity(provider: .plex, id: "server-2")
            )
        ]

        let action = QuickActionDownloadActionPolicy.action(for: media, downloadItems: downloads)

        XCTAssertEqual(action, .download)
    }

    func test_seriesUsesEpisodeDownloadsToRouteToDownloads() {
        let media = makeMediaItem(id: "show-1", type: .series)
        let downloads = [
            makeDownloadItem(
                itemID: "episode-1",
                type: .episode,
                status: .downloading,
                parentRatingKey: "season-1",
                grandparentRatingKey: "show-1"
            )
        ]

        let action = QuickActionDownloadActionPolicy.action(for: media, downloadItems: downloads)

        XCTAssertEqual(action, .goToDownloads)
    }

    func test_seasonUsesEpisodeDownloadsToRouteToDownloads() {
        let media = makeMediaItem(id: "season-1", type: .season)
        let downloads = [
            makeDownloadItem(
                itemID: "episode-1",
                type: .episode,
                status: .queued,
                parentRatingKey: "season-1",
                grandparentRatingKey: "show-1"
            )
        ]

        let action = QuickActionDownloadActionPolicy.action(for: media, downloadItems: downloads)

        XCTAssertEqual(action, .goToDownloads)
    }

    private func makeMediaItem(id: String, type: MediaKind) -> MediaItem {
        MediaItem(
            id: id,
            identity: MediaIdentity(server: server, itemID: id),
            guid: "guid://\(id)",
            summary: nil,
            title: id,
            type: type,
            parentRatingKey: nil,
            grandparentRatingKey: nil,
            genres: [],
            year: nil,
            duration: nil,
            videoResolution: nil,
            rating: nil,
            ratings: [],
            contentRating: nil,
            studio: nil,
            tagline: nil,
            thumbPath: nil,
            artPath: nil,
            artworkCornerColors: nil,
            viewOffset: nil,
            viewCount: nil,
            childCount: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            grandparentTitle: nil,
            parentTitle: nil,
            parentIndex: nil,
            index: nil,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil
        )
    }

    private func makeDownloadItem(
        itemID: String,
        type: MediaKind,
        status: DownloadStatus,
        parentRatingKey: String? = nil,
        grandparentRatingKey: String? = nil,
        server: ServerIdentity? = nil
    ) -> DownloadItem {
        DownloadItem(
            id: "download-\(itemID)",
            status: status,
            progress: 0,
            bytesWritten: 0,
            totalBytes: 0,
            taskIdentifier: nil,
            errorMessage: nil,
            metadata: DownloadedMediaMetadata(
                identity: MediaIdentity(server: server ?? self.server, itemID: itemID),
                guid: "guid://\(itemID)",
                type: type,
                title: itemID,
                summary: nil,
                genres: [],
                year: nil,
                duration: nil,
                viewCount: nil,
                contentRating: nil,
                studio: nil,
                tagline: nil,
                parentRatingKey: parentRatingKey,
                grandparentRatingKey: grandparentRatingKey,
                grandparentTitle: nil,
                parentTitle: nil,
                parentIndex: nil,
                index: nil,
                posterFileName: nil,
                videoFileName: "video",
                fileSize: nil,
                requestedQuality: .original,
                effectiveQuality: .original,
                audioTitle: nil,
                subtitleTitle: nil,
                createdAt: Date()
            )
        )
    }
}
