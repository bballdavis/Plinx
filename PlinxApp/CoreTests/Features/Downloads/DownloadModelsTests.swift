import Foundation
@testable import Plinx
import Testing

@MainActor
struct DownloadModelsTests {
    private let server = ServerIdentity(provider: .plex, id: "server-1")

    @Test func `a failed download can be retried`() {
        let failed = DownloadItem.make(id: "download-1", itemID: "movie-1", server: server, status: .failed)

        #expect(failed.canRetry(among: [failed]))
    }

    @Test(arguments: [DownloadStatus.queued, .preparing, .downloading, .completed])
    func `only a failed download can be retried`(status: DownloadStatus) {
        let item = DownloadItem.make(id: "download-1", itemID: "movie-1", server: server, status: status)

        #expect(!item.canRetry(among: [item]))
    }

    @Test func `a failed download cannot be retried once the same media was downloaded again`() {
        let failed = DownloadItem.make(
            id: "download-1", itemID: "movie-1", server: server, status: .failed, ownerID: "user-1",
        )
        let again = DownloadItem.make(
            id: "download-2", itemID: "movie-1", server: server, status: .downloading, ownerID: "user-1",
        )

        #expect(!failed.canRetry(among: [failed, again]))
    }

    @Test func `other failed copies or other users' downloads do not block a retry`() {
        let failed = DownloadItem.make(
            id: "download-1", itemID: "movie-1", server: server, status: .failed, ownerID: "user-1",
        )
        let otherFailed = DownloadItem.make(
            id: "download-2", itemID: "movie-1", server: server, status: .failed, ownerID: "user-1",
        )
        let otherUser = DownloadItem.make(
            id: "download-3", itemID: "movie-1", server: server, status: .completed, ownerID: "user-2",
        )

        #expect(failed.canRetry(among: [failed, otherFailed, otherUser]))
    }

    // Whether a finished transfer is kept as a video is covered with `DownloadIntegrityValidator` in
    // `DownloadIntegrityTests`.
}
