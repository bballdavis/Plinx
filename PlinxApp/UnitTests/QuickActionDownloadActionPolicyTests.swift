import XCTest
@testable import Plinx

final class QuickActionDownloadActionPolicyTests: XCTestCase {
    func test_movieWithoutDownloadShowsDownloadAction() {
        let media = makeMediaItem(id: "movie-1", type: .movie)

        let action = QuickActionDownloadActionPolicy.action(for: media, downloadItems: [])

        XCTAssertEqual(action, .download)
    }

    func test_completedMovieShowsGoToDownloadsAction() {
        let media = makeMediaItem(id: "movie-1", type: .movie)
        let downloads = [makeDownloadItem(ratingKey: "movie-1", type: .movie, status: .completed)]

        let action = QuickActionDownloadActionPolicy.action(for: media, downloadItems: downloads)

        XCTAssertEqual(action, .goToDownloads)
    }

    func test_failedMovieStillShowsDownloadAction() {
        let media = makeMediaItem(id: "movie-1", type: .movie)
        let downloads = [makeDownloadItem(ratingKey: "movie-1", type: .movie, status: .failed)]

        let action = QuickActionDownloadActionPolicy.action(for: media, downloadItems: downloads)

        XCTAssertEqual(action, .download)
    }

    func test_showUsesEpisodeDownloadsToRouteToDownloads() {
        let media = makeMediaItem(id: "show-1", type: .show)
        let downloads = [
            makeDownloadItem(
                ratingKey: "episode-1",
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
                ratingKey: "episode-1",
                type: .episode,
                status: .queued,
                parentRatingKey: "season-1",
                grandparentRatingKey: "show-1"
            )
        ]

        let action = QuickActionDownloadActionPolicy.action(for: media, downloadItems: downloads)

        XCTAssertEqual(action, .goToDownloads)
    }

    private func makeMediaItem(id: String, type: PlexItemType) -> MediaItem {
        MediaItem(
            id: id,
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
            contentRating: nil,
            studio: nil,
            tagline: nil,
            thumbPath: nil,
            artPath: nil,
            ultraBlurColors: nil,
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
        ratingKey: String,
        type: PlexItemType,
        status: DownloadStatus,
        parentRatingKey: String? = nil,
        grandparentRatingKey: String? = nil
    ) -> DownloadItem {
        DownloadItem(
            id: "download-\(ratingKey)",
            status: status,
            progress: 0,
            bytesWritten: 0,
            totalBytes: 0,
            taskIdentifier: nil,
            errorMessage: nil,
            metadata: DownloadedMediaMetadata(
                ratingKey: ratingKey,
                guid: "guid://\(ratingKey)",
                type: type,
                title: ratingKey,
                summary: nil,
                genres: [],
                year: nil,
                duration: nil,
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
                createdAt: Date()
            )
        )
    }
}