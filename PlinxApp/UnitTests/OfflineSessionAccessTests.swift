@testable import Plinx
import PlinxCore
import XCTest

/// Which downloads a session may open, signed out, after a profile switch, or with an unknown owner.
///
/// Pre-fork Plinx decided this with `PlinxSessionAccessCoordinator` and a persisted offline snapshot of one
/// server/profile identity. The coordinator is gone: `DownloadManager` now activates the owners (`MediaOwner`:
/// provider, server and server user) of the session's services (`activateSession(services:)`), sign-out activates
/// none (`PlinxSignOut` calls `activateOwners([])`), and `DownloadAccessPolicy` lets a profile open only downloads
/// whose `ownerID` is active. These tests keep the old fail-closed guarantees on that path: no session means no
/// downloads, a profile switch hides the previous profile's downloads, and a download without an owner is never
/// handed to whichever profile is active. The coordinator's connecting/offline/online states and reconnect
/// handling have no counterpart in the absorbed session stack and are not tested here.
///
/// The snapshot (`plinx.offlineSession.v1`) is still read in one case: the first launch after the update, offline,
/// when the one-time update to accounts and profiles cannot reach plex.tv (`migrationFailed`). Then only the profile
/// it names owns the offline Downloads root (`PlinxLegacyOfflineSession`), so the family keeps that profile's
/// downloads and nothing more.
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

    // MARK: - First offline launch after the update

    /// What pre-fork Plinx's `KeychainOfflineSessionPersistence` wrote: a JSON-encoded `OfflineSessionSnapshot`.
    private let preForkSnapshot = """
    {"identity":{"serverIdentifier":"server","profileIdentifier":"profile"},\
    "serverName":"Living Room","profileName":"Kid","savedAt":786000000}
    """

    func test_snapshotNamesTheOwnerItsProfilesDownloadsWereGiven() throws {
        let owner = try XCTUnwrap(PlinxLegacyOfflineSession.owner(fromSnapshot: Data(preForkSnapshot.utf8)))

        XCTAssertEqual(owner, profileA)
        // Pre-fork downloads get their owner from the record kept beside them, written from the same identity.
        let record = Data(#"{"download":{"serverIdentifier":"server","profileIdentifier":"profile"}}"#.utf8)
        XCTAssertEqual(LegacyDownloadOwnership.recordedOwners(from: record)?["download"]?.id, owner.id)
    }

    func test_snapshotIsReadFromThePreForkKeychainItem() {
        let store = InMemorySecureStore([PlinxSignOut.legacyOfflineSessionKey: preForkSnapshot])

        XCTAssertEqual(PlinxLegacyOfflineSession.snapshotOwner(secureStore: store), profileA)
    }

    func test_missingUnreadableOrIncompleteSnapshotGivesNoOwner() {
        XCTAssertNil(PlinxLegacyOfflineSession.snapshotOwner(secureStore: InMemorySecureStore()))

        let unreadable = InMemorySecureStore([PlinxSignOut.legacyOfflineSessionKey: preForkSnapshot])
        unreadable.failsReads = true
        XCTAssertNil(PlinxLegacyOfflineSession.snapshotOwner(secureStore: unreadable))

        let incomplete = [
            "not json",
            #"{"serverName":"Living Room"}"#,
            #"{"identity":{"serverIdentifier":"","profileIdentifier":"profile"}}"#,
            #"{"identity":{"serverIdentifier":"server","profileIdentifier":""}}"#,
        ]
        for snapshot in incomplete {
            let store = InMemorySecureStore([PlinxSignOut.legacyOfflineSessionKey: snapshot])
            XCTAssertNil(PlinxLegacyOfflineSession.snapshotOwner(secureStore: store), snapshot)
        }
    }

    func test_snapshotOwnsDownloadsOnlyWhileTheUpdateFailedOffline() {
        let owner = profileA
        XCTAssertEqual(
            PlinxLegacyOfflineSession.fallbackOwner(status: .migrationFailed, hasNetworkPath: false) { owner },
            owner
        )

        // With a network the update is retried, and in any other state the session's services decide: the
        // snapshot is not even read.
        var reads = 0
        let readSnapshot: () -> MediaOwner? = {
            reads += 1
            return owner
        }
        XCTAssertNil(PlinxLegacyOfflineSession.fallbackOwner(
            status: .migrationFailed,
            hasNetworkPath: true,
            snapshotOwner: readSnapshot
        ))
        let otherStatuses: [SessionManager.Status] = [.hydrating, .needsAccount, .needsProfileSelection, .ready]
        for status in otherStatuses {
            XCTAssertNil(PlinxLegacyOfflineSession.fallbackOwner(
                status: status,
                hasNetworkPath: false,
                snapshotOwner: readSnapshot
            ))
        }
        XCTAssertEqual(reads, 0)

        // No snapshot: no owner, so the recovery card is shown alone.
        XCTAssertNil(PlinxLegacyOfflineSession.fallbackOwner(status: .migrationFailed, hasNetworkPath: false) { nil })
    }

    func test_snapshotOwnerSeesOnlyItsOwnAllowedDownloads() throws {
        let owner = try XCTUnwrap(PlinxLegacyOfflineSession.owner(fromSnapshot: Data(preForkSnapshot.utf8)))
        let own = download(id: "own", ownerID: profileA.id)
        let otherProfile = download(id: "other-profile", ownerID: profileB.id)
        let unowned = download(id: "unowned", ownerID: nil)
        let blocked = download(id: "blocked", ownerID: profileA.id, contentRating: "R")

        let policy = DownloadAccessPolicy(activeOwnerIDs: [owner.id], gate: gate)

        XCTAssertEqual(policy.filter([own, otherProfile, unowned, blocked]).map(\.id), ["own"])
        XCTAssertEqual(policy.decision(for: otherProfile), .wrongOwner)
        XCTAssertEqual(policy.decision(for: unowned), .missingOwner)
        XCTAssertEqual(policy.decision(for: blocked), .blockedByContentPolicy)
    }

    func test_snapshotIsRetiredOnceTheUpdateFinished() {
        XCTAssertFalse(PlinxLegacyOfflineSession.updateHasFinished(.hydrating))
        XCTAssertFalse(PlinxLegacyOfflineSession.updateHasFinished(.migrationFailed))
        XCTAssertTrue(PlinxLegacyOfflineSession.updateHasFinished(.needsAccount))
        XCTAssertTrue(PlinxLegacyOfflineSession.updateHasFinished(.needsProfileSelection))
        XCTAssertTrue(PlinxLegacyOfflineSession.updateHasFinished(.ready))
    }

    /// The first launch after the update, offline: plex.tv cannot name the saved token's user, so the one-time update
    /// fails (`SessionManager.hydrate` reports `migrationFailed`) and no account is guessed from the snapshot. The
    /// snapshot and the old sign-in stay for the retry, and the snapshot's profile alone gets its own downloads.
    func test_offlineFirstLaunchAfterTheUpdateKeepsOnlyTheSnapshotProfilesDownloads() async throws {
        let defaults = TestDefaults.make()
        let secureStore = InMemorySecureStore([
            MultiServerMigration.LegacyKeys.plexToken: "pre-fork-token",
            PlinxSignOut.legacyOfflineSessionKey: preForkSnapshot,
        ])
        defaults.set("plex", forKey: MultiServerMigration.LegacyKeys.provider)
        defaults.set(server.id, forKey: MultiServerMigration.LegacyKeys.plexServerIdentifier)
        let accounts = AccountStore(userDefaults: defaults, secureStore: secureStore)
        let profiles = ProfileStore(userDefaults: defaults)
        let migration = MultiServerMigration(
            defaults: defaults,
            secureStore: secureStore,
            accountStore: accounts,
            profileStore: profiles,
            settingsManager: SettingsManager(userDefaults: defaults),
            favoritesStore: FavoritesStore(userDefaults: defaults),
            resolvePlexUser: { _ in throw URLError(.notConnectedToInternet) },
        )

        let outcome = await migration.run()

        XCTAssertEqual(outcome, .failed)
        XCTAssertTrue(accounts.accounts.isEmpty)
        XCTAssertNil(profiles.activeProfileID)
        XCTAssertEqual(secureStore.values[MultiServerMigration.LegacyKeys.plexToken], "pre-fork-token")
        XCTAssertEqual(secureStore.values[PlinxSignOut.legacyOfflineSessionKey], preForkSnapshot)

        let fallbackOwner = PlinxLegacyOfflineSession.fallbackOwner(status: .migrationFailed, hasNetworkPath: false) {
            PlinxLegacyOfflineSession.snapshotOwner(secureStore: secureStore)
        }
        let owner = try XCTUnwrap(fallbackOwner)
        XCTAssertEqual(owner, profileA)

        let own = download(id: "own", ownerID: profileA.id)
        let otherProfile = download(id: "other-profile", ownerID: profileB.id)
        let unowned = download(id: "unowned", ownerID: nil)
        let policy = DownloadAccessPolicy(activeOwnerIDs: [owner.id], gate: gate)
        XCTAssertEqual(policy.filter([own, otherProfile, unowned]).map(\.id), ["own"])
    }

    // MARK: - Helpers

    private func download(id: String, ownerID: String?, contentRating: String = "G") -> DownloadItem {
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
            contentRating: contentRating,
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
