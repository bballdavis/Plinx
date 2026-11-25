@testable import Plinx
import PlinxCore
import XCTest

/// Which downloads a session may open, signed out, after a profile switch, or with an unknown owner.
///
/// Pre-fork Plinx decided this with `PlinxSessionAccessCoordinator` and a persisted offline snapshot of one
/// server/profile identity. Both are gone: `DownloadManager` now activates the owners (`MediaOwner`: provider,
/// server and server user) of the session's services (`activateSession(services:)`), sign-out activates none
/// (`PlinxSignOut` calls `activateOwners([])`), and `DownloadAccessPolicy` lets a profile open only downloads whose
/// `ownerID` is active. These tests keep the old fail-closed guarantees on that path: no session means no
/// downloads, a profile switch hides the previous profile's downloads, and a download without an owner is never
/// handed to whichever profile is active. The coordinator's connecting/offline/online states and reconnect
/// handling have no counterpart in the absorbed session stack and are not tested here.
@MainActor
final class OfflineSessionAccessTests: XCTestCase {
    private let server = ServerIdentity(provider: .plex, id: "server")
    private lazy var profileA = MediaOwner(server: server, userID: "profile")
    private lazy var profileB = MediaOwner(server: server, userID: "profile-b")
    /// The strict default ceiling; every fixture below is rated G so only ownership decides.
    private lazy var gate = ContentSafetyGate(policy: .ratingOnly())

    func test_signedOutSessionOpensNoDownload() {
        let owned = download(id: "owned", ownerID: profileA.id)
        // Sign-out activates no owner at all.
        let policy = DownloadAccessPolicy(activeOwnerIDs: [], gate: gate)

        XCTAssertTrue(policy.isAllowedByContentPolicy(owned))
        XCTAssertEqual(policy.decision(for: owned), .wrongOwner)
        XCTAssertEqual(DownloadTapAction.resolve(for: owned, decision: policy.decision(for: owned)), .none)
        XCTAssertTrue(policy.filter([owned]).isEmpty)
    }

    func test_profileSwitchHidesThePreviousProfilesDownloads() {
        let fromA = download(id: "from-a", ownerID: profileA.id)
        let fromB = download(id: "from-b", ownerID: profileB.id)

        let afterSwitch = DownloadAccessPolicy(activeOwnerIDs: [profileB.id], gate: gate)

        XCTAssertEqual(afterSwitch.decision(for: fromA), .wrongOwner)
        XCTAssertEqual(afterSwitch.decision(for: fromB), .allowed)
        XCTAssertEqual(afterSwitch.filter([fromA, fromB]).map(\.id), ["from-b"])
    }

    func test_sameProfileNameOnAnotherServerIsAnotherOwner() {
        let otherServer = ServerIdentity(provider: .plex, id: "new-server")
        let sameUserElsewhere = MediaOwner(server: otherServer, userID: profileA.userID)
        let owned = download(id: "owned", ownerID: profileA.id)

        XCTAssertNotEqual(sameUserElsewhere.id, profileA.id)
        let policy = DownloadAccessPolicy(activeOwnerIDs: [sameUserElsewhere.id], gate: gate)
        XCTAssertEqual(policy.decision(for: owned), .wrongOwner)
    }

    func test_downloadWithoutOwnerIsNeverHandedToTheActiveProfile() {
        let unowned = download(id: "unowned", ownerID: nil)

        let policy = DownloadAccessPolicy(activeOwnerIDs: [profileA.id, profileB.id], gate: gate)

        XCTAssertEqual(policy.decision(for: unowned), .missingOwner)
        XCTAssertEqual(DownloadTapAction.resolve(for: unowned, decision: policy.decision(for: unowned)), .none)
        XCTAssertTrue(policy.filter([unowned]).isEmpty)
    }

    // MARK: - Helpers

    private func download(id: String, ownerID: String?) -> DownloadItem {
        let metadata = DownloadedMediaMetadata(
            identity: MediaIdentity(server: server, itemID: "item-\(id)"),
            guid: "plex://movie/\(id)",
            type: .movie,
            title: "Movie \(id)",
            summary: nil,
            genres: [],
            year: 2020,
            duration: 5400,
            viewCount: nil,
            contentRating: "G",
            studio: nil,
            tagline: nil,
            parentRatingKey: nil,
            grandparentRatingKey: nil,
            grandparentTitle: nil,
            parentTitle: nil,
            parentIndex: nil,
            index: nil,
            posterFileName: nil,
            videoFileName: "video.mp4",
            fileSize: 1024,
            requestedQuality: .original,
            effectiveQuality: .original,
            audioTitle: nil,
            subtitleTitle: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        return DownloadItem(
            id: id,
            status: .completed,
            progress: 1,
            bytesWritten: 1024,
            totalBytes: 1024,
            taskIdentifier: nil,
            remoteReference: nil,
            trackPreference: nil,
            errorMessage: nil,
            metadata: metadata,
            ownerID: ownerID,
        )
    }
}
