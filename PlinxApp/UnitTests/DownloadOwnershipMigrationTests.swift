@testable import Plinx
import XCTest

/// Pre-fork Plinx kept download ownership in UserDefaults (`plinx.downloadOwnership.v1`). These tests pin the
/// one-time import that turns it into `ownerID`, so an update never costs a family its kids' downloads, and never
/// hands a download to a profile the record does not name.
@MainActor
final class DownloadOwnershipMigrationTests: XCTestCase {
    private let server = ServerIdentity(provider: .plex, id: "server-machine-1")
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "DownloadOwnershipMigrationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Version 2 envelope

    func test_v2Envelope_assignsRecordedOwnersAndLeavesEveryOtherDownloadUnowned() throws {
        store("""
        {
          "version": 2,
          "owned": {
            "kid-movie": {"serverIdentifier": "server-machine-1", "profileIdentifier": "kid-uuid"},
            "parent-episode": {"serverIdentifier": "server-machine-1", "profileIdentifier": "parent-uuid"}
          },
          "grandfatheredLegacy": ["old-movie"],
          "unprovenanced": ["mystery-movie"]
        }
        """)
        let items = [
            legacyItem(id: "kid-movie", itemID: "101"),
            legacyItem(id: "parent-episode", itemID: "202"),
            legacyItem(id: "old-movie", itemID: "303"),
            legacyItem(id: "mystery-movie", itemID: "404"),
            legacyItem(id: "unlisted-movie", itemID: "505"),
        ]
        var saved: [[DownloadItem]] = []

        let outcome = LegacyDownloadOwnership.migrate(items, defaults: defaults) { saved.append($0) }

        let kid = MediaOwner(server: server, userID: "kid-uuid")
        let parent = MediaOwner(server: server, userID: "parent-uuid")
        XCTAssertEqual(outcome, .migrated(["kid-movie": kid, "parent-episode": parent]))
        XCTAssertEqual(saved.count, 1)
        let migrated = try XCTUnwrap(saved.first)
        XCTAssertEqual(owner(of: "kid-movie", in: migrated), "plex|server-machine-1|kid-uuid")
        XCTAssertEqual(owner(of: "parent-episode", in: migrated), parent.id)
        // Grandfathered, unprovenanced and unlisted downloads stay parent-only.
        XCTAssertNil(owner(of: "old-movie", in: migrated))
        XCTAssertNil(owner(of: "mystery-movie", in: migrated))
        XCTAssertNil(owner(of: "unlisted-movie", in: migrated))
        // The record names the server pre-fork downloads did not store.
        let kidMovie = try XCTUnwrap(migrated.first { $0.id == "kid-movie" })
        XCTAssertEqual(kidMovie.identity, MediaIdentity(server: server, itemID: "101"))
        XCTAssertNil(migrated.first { $0.id == "old-movie" }?.identity)
        XCTAssertNil(defaults.object(forKey: LegacyDownloadOwnership.defaultsKey))
    }

    func test_ownerIDUsesTheSameFormAsThePlexServicesOwner() {
        // Plex services own their data as `MediaOwner(server: <machine id>, userID: <Home user UUID>)`.
        let owners = LegacyDownloadOwnership.recordedOwners(from: Data("""
        {"d": {"serverIdentifier": "machine", "profileIdentifier": "home-user-uuid"}}
        """.utf8))
        XCTAssertEqual(
            owners?["d"],
            MediaOwner(server: ServerIdentity(provider: .plex, id: "machine"), userID: "home-user-uuid"),
        )
        XCTAssertEqual(owners?["d"]?.id, "plex|machine|home-user-uuid")
    }

    // MARK: - First (bare dictionary) format

    func test_legacyDictionary_assignsRecordedOwners() throws {
        store("""
        {"kid-movie": {"serverIdentifier": "server-machine-1", "profileIdentifier": "kid-uuid"}}
        """)
        let items = [legacyItem(id: "kid-movie", itemID: "101"), legacyItem(id: "old-movie", itemID: "303")]
        var saved: [DownloadItem] = []

        let outcome = LegacyDownloadOwnership.migrate(items, defaults: defaults) { saved = $0 }

        XCTAssertEqual(outcome, .migrated(["kid-movie": MediaOwner(server: server, userID: "kid-uuid")]))
        XCTAssertEqual(owner(of: "kid-movie", in: saved), "plex|server-machine-1|kid-uuid")
        XCTAssertNil(owner(of: "old-movie", in: saved))
        XCTAssertNil(defaults.object(forKey: LegacyDownloadOwnership.defaultsKey))
    }

    func test_entriesWithAnEmptyServerOrProfileAreSkipped() {
        store("""
        {
          "no-server": {"serverIdentifier": "", "profileIdentifier": "kid-uuid"},
          "no-profile": {"serverIdentifier": "server-machine-1", "profileIdentifier": ""}
        }
        """)
        let items = [legacyItem(id: "no-server", itemID: "1"), legacyItem(id: "no-profile", itemID: "2")]
        var saveCount = 0

        let outcome = LegacyDownloadOwnership.migrate(items, defaults: defaults) { _ in saveCount += 1 }

        XCTAssertEqual(outcome, .migrated([:]))
        XCTAssertEqual(saveCount, 0)
    }

    // MARK: - Fail closed

    func test_corruptRecord_leavesEverythingUnownedAndKeepsTheRecord() {
        defaults.set(Data("not-json".utf8), forKey: LegacyDownloadOwnership.defaultsKey)
        var saveCount = 0

        let outcome = LegacyDownloadOwnership.migrate(
            [legacyItem(id: "kid-movie", itemID: "101")],
            defaults: defaults,
        ) { _ in saveCount += 1 }

        XCTAssertEqual(outcome, .unreadable)
        XCTAssertEqual(saveCount, 0)
        XCTAssertNotNil(defaults.object(forKey: LegacyDownloadOwnership.defaultsKey))
    }

    func test_unknownEnvelopeVersionOrNonDataValue_isUnreadable() {
        store("""
        {"version": 3, "owned": {}, "grandfatheredLegacy": [], "unprovenanced": []}
        """)
        XCTAssertEqual(LegacyDownloadOwnership.migrate([], defaults: defaults) { _ in }, .unreadable)

        defaults.set("not data", forKey: LegacyDownloadOwnership.defaultsKey)
        XCTAssertEqual(LegacyDownloadOwnership.migrate([], defaults: defaults) { _ in }, .unreadable)
        XCTAssertNotNil(defaults.object(forKey: LegacyDownloadOwnership.defaultsKey))
    }

    func test_failedSave_keepsTheRecordForTheNextLaunch() {
        store("""
        {"kid-movie": {"serverIdentifier": "server-machine-1", "profileIdentifier": "kid-uuid"}}
        """)
        struct SaveFailure: Error {}

        let outcome = LegacyDownloadOwnership.migrate(
            [legacyItem(id: "kid-movie", itemID: "101")],
            defaults: defaults,
        ) { _ in throw SaveFailure() }

        XCTAssertEqual(outcome, .saveFailed)
        XCTAssertNotNil(defaults.object(forKey: LegacyDownloadOwnership.defaultsKey))
    }

    // MARK: - Idempotence

    func test_secondRunChangesNothing() throws {
        store("""
        {"kid-movie": {"serverIdentifier": "server-machine-1", "profileIdentifier": "kid-uuid"}}
        """)
        var items = [legacyItem(id: "kid-movie", itemID: "101"), legacyItem(id: "old-movie", itemID: "303")]
        _ = LegacyDownloadOwnership.migrate(items, defaults: defaults) { items = $0 }
        let afterFirstRun = items
        var saveCount = 0

        let outcome = LegacyDownloadOwnership.migrate(items, defaults: defaults) { _ in saveCount += 1 }

        XCTAssertEqual(outcome, .nothingStored)
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(items, afterFirstRun)

        // Even with the record still present, already assigned downloads are not assigned again.
        let owners = try XCTUnwrap(LegacyDownloadOwnership.recordedOwners(from: Data("""
        {"kid-movie": {"serverIdentifier": "server-machine-1", "profileIdentifier": "kid-uuid"}}
        """.utf8)))
        let rerun = LegacyDownloadOwnership.assigningOwners(owners, to: afterFirstRun)
        XCTAssertEqual(rerun.items, afterFirstRun)
        XCTAssertTrue(rerun.assigned.isEmpty)
    }

    func test_nothingStored_isANoOp() {
        var saveCount = 0
        let items = [legacyItem(id: "old-movie", itemID: "303")]

        XCTAssertEqual(LegacyDownloadOwnership.migrate(items, defaults: defaults) { _ in saveCount += 1 }, .nothingStored)
        XCTAssertEqual(saveCount, 0)
    }

    // MARK: - Existing owners

    func test_downloadsThatAlreadyHaveAnOwnerAreUntouched() {
        store("""
        {
          "enrolled-movie": {"serverIdentifier": "server-machine-1", "profileIdentifier": "kid-uuid"},
          "other-server": {"serverIdentifier": "server-machine-1", "profileIdentifier": "kid-uuid"}
        }
        """)
        var enrolled = legacyItem(id: "enrolled-movie", itemID: "101")
        enrolled.metadata.identity = MediaIdentity(server: server, itemID: "101")
        enrolled.ownerID = MediaOwner(server: server, userID: "parent-uuid").id
        // A download whose stored server differs from the recorded one is not reassigned either.
        var otherServer = legacyItem(id: "other-server", itemID: "202")
        let elsewhere = ServerIdentity(provider: .plex, id: "server-machine-2")
        otherServer.metadata.identity = MediaIdentity(server: elsewhere, itemID: "202")
        var saveCount = 0

        let outcome = LegacyDownloadOwnership.migrate([enrolled, otherServer], defaults: defaults) { _ in
            saveCount += 1
        }

        XCTAssertEqual(outcome, .migrated([:]))
        XCTAssertEqual(saveCount, 0)
        let result = LegacyDownloadOwnership.assigningOwners(
            [
                "enrolled-movie": MediaOwner(server: server, userID: "kid-uuid"),
                "other-server": MediaOwner(server: server, userID: "kid-uuid"),
            ],
            to: [enrolled, otherServer],
        )
        XCTAssertEqual(result.items, [enrolled, otherServer])
        XCTAssertEqual(result.items.first?.ownerID, "plex|server-machine-1|parent-uuid")
        XCTAssertNil(result.items.last?.ownerID)
        XCTAssertNil(defaults.object(forKey: LegacyDownloadOwnership.defaultsKey))
    }

    // MARK: - Helpers

    private func store(_ json: String) {
        defaults.set(Data(json.utf8), forKey: LegacyDownloadOwnership.defaultsKey)
    }

    private func owner(of downloadID: String, in items: [DownloadItem]) -> String? {
        items.first { $0.id == downloadID }?.ownerID
    }

    /// A download as pre-fork Plinx left it: no owner, and no server stored with its metadata.
    private func legacyItem(id: String, itemID: String) -> DownloadItem {
        var metadata = DownloadedMediaMetadata(
            identity: MediaIdentity(server: server, itemID: itemID),
            guid: "plex://movie/\(itemID)",
            type: .movie,
            title: "Movie \(itemID)",
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
        metadata.identity = nil
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
        )
    }
}
