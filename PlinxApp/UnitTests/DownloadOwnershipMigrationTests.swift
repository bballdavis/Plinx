@testable import Plinx
import XCTest

/// Pre-fork Plinx kept download ownership in UserDefaults (`plinx.downloadOwnership.v1`) and in its download index
/// (`index.json`, `accessScope`). These tests pin the one-time imports that turn both into `ownerID`, so an update
/// never costs a family its kids' downloads or their offline resume points, and never hands a download to a profile
/// the records do not name.
@MainActor
final class DownloadOwnershipMigrationTests: XCTestCase {
    private let server = ServerIdentity(provider: .plex, id: "server-machine-1")
    /// The server the pre-fork download index entries below were enrolled on.
    private let indexServer = ServerIdentity(provider: .plex, id: "server-a")
    private let kidScope = DownloadAccessScope(serverIdentifier: "server-a", accessScopeIdentifier: "kid-uuid")
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var offlineDatabase: TestOfflineDatabase?
    private var indexDirectory: URL?

    override func setUp() {
        super.setUp()
        suiteName = "DownloadOwnershipMigrationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        offlineDatabase = nil
        if let indexDirectory {
            try? FileManager.default.removeItem(at: indexDirectory)
        }
        indexDirectory = nil
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

        let outcome = LegacyDownloadOwnership.migrate(items, indexState: .loaded, defaults: defaults) {
            saved.append($0)
        }

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

        let outcome = LegacyDownloadOwnership.migrate(items, indexState: .loaded, defaults: defaults) { saved = $0 }

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

        let outcome = LegacyDownloadOwnership.migrate(items, indexState: .loaded, defaults: defaults) { _ in
            saveCount += 1
        }

        XCTAssertEqual(outcome, .migrated([:]))
        XCTAssertEqual(saveCount, 0)
    }

    // MARK: - Fail closed

    func test_corruptRecord_leavesEverythingUnownedAndKeepsTheRecord() {
        defaults.set(Data("not-json".utf8), forKey: LegacyDownloadOwnership.defaultsKey)
        var saveCount = 0

        let outcome = LegacyDownloadOwnership.migrate(
            [legacyItem(id: "kid-movie", itemID: "101")],
            indexState: .loaded,
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
        XCTAssertEqual(
            LegacyDownloadOwnership.migrate([], indexState: .loaded, defaults: defaults) { _ in },
            .unreadable,
        )

        defaults.set("not data", forKey: LegacyDownloadOwnership.defaultsKey)
        XCTAssertEqual(
            LegacyDownloadOwnership.migrate([], indexState: .loaded, defaults: defaults) { _ in },
            .unreadable,
        )
        XCTAssertNotNil(defaults.object(forKey: LegacyDownloadOwnership.defaultsKey))
    }

    func test_failedSave_keepsTheRecordForTheNextLaunch() {
        store("""
        {"kid-movie": {"serverIdentifier": "server-machine-1", "profileIdentifier": "kid-uuid"}}
        """)
        struct SaveFailure: Error {}

        let outcome = LegacyDownloadOwnership.migrate(
            [legacyItem(id: "kid-movie", itemID: "101")],
            indexState: .loaded,
            defaults: defaults,
        ) { _ in throw SaveFailure() }

        XCTAssertEqual(outcome, .saveFailed)
        XCTAssertNotNil(defaults.object(forKey: LegacyDownloadOwnership.defaultsKey))
    }

    func test_incompleteDownloadList_defersTheImportAndKeepsTheRecord() {
        store("""
        {"kid-movie": {"serverIdentifier": "server-machine-1", "profileIdentifier": "kid-uuid"}}
        """)

        for state in [DownloadPersistedIndexState.corrupt, .unreadable, .missing] {
            var saveCount = 0
            let outcome = LegacyDownloadOwnership.migrate(
                [legacyItem(id: "kid-movie", itemID: "101")],
                indexState: state,
                defaults: defaults,
            ) { _ in saveCount += 1 }

            XCTAssertEqual(outcome, .deferred, "\(state)")
            XCTAssertEqual(saveCount, 0, "\(state)")
            XCTAssertNotNil(defaults.object(forKey: LegacyDownloadOwnership.defaultsKey), "\(state)")
        }
    }

    // MARK: - Idempotence

    func test_secondRunChangesNothing() throws {
        store("""
        {"kid-movie": {"serverIdentifier": "server-machine-1", "profileIdentifier": "kid-uuid"}}
        """)
        var items = [legacyItem(id: "kid-movie", itemID: "101"), legacyItem(id: "old-movie", itemID: "303")]
        _ = LegacyDownloadOwnership.migrate(items, indexState: .loaded, defaults: defaults) { items = $0 }
        let afterFirstRun = items
        var saveCount = 0

        let outcome = LegacyDownloadOwnership.migrate(items, indexState: .loaded, defaults: defaults) { _ in
            saveCount += 1
        }

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

        let outcome = LegacyDownloadOwnership.migrate(items, indexState: .loaded, defaults: defaults) { _ in
            saveCount += 1
        }

        XCTAssertEqual(outcome, .nothingStored)
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

        let outcome = LegacyDownloadOwnership.migrate(
            [enrolled, otherServer],
            indexState: .loaded,
            defaults: defaults,
        ) { _ in
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

    // MARK: - Pre-fork download index (`accessScope`)

    func test_indexAccessScope_givesTheDownloadToThatProfile() throws {
        let entry = try indexEntry(indexEntryJSON(accessScope: kidScope))

        XCTAssertEqual(entry.enrolledOwner, MediaOwner(server: indexServer, userID: "kid-uuid"))
        XCTAssertEqual(entry.migratedItem.ownerID, "plex|server-a|kid-uuid")
        // The scope names the server the pre-fork metadata did not store.
        XCTAssertEqual(entry.migratedItem.identity, MediaIdentity(server: indexServer, itemID: "123"))
    }

    func test_indexAccessScopeWithAnEmptyServerOrProfile_leavesTheDownloadUnowned() throws {
        let scopes = [
            DownloadAccessScope(serverIdentifier: "", accessScopeIdentifier: "kid-uuid"),
            DownloadAccessScope(serverIdentifier: "server-a", accessScopeIdentifier: ""),
        ]
        for scope in scopes {
            let entry = try indexEntry(indexEntryJSON(accessScope: scope))

            XCTAssertNil(entry.enrolledOwner, "\(scope)")
            XCTAssertNil(entry.migratedItem.ownerID, "\(scope)")
            XCTAssertNil(entry.migratedItem.identity, "\(scope)")
        }
    }

    func test_indexAccessScopeForAnotherServer_leavesTheDownloadUnowned() throws {
        let storedServers = [
            ServerIdentity(provider: .plex, id: "server-b"),
            // Pre-fork Plinx only ever enrolled Plex downloads.
            ServerIdentity(provider: .jellyfin, id: "server-a"),
        ]
        for storedServer in storedServers {
            let entry = try indexEntry(indexEntryJSON(accessScope: kidScope, storedServer: storedServer))

            XCTAssertNil(entry.enrolledOwner, "\(storedServer)")
            XCTAssertNil(entry.migratedItem.ownerID, "\(storedServer)")
            XCTAssertEqual(entry.migratedItem.identity?.server, storedServer)
        }
    }

    func test_indexAccessScope_replacesAStrayOwnerIDAndNeverKeepsIt() throws {
        let stray = "plex|server-a|someone-else"

        let scoped = try indexEntry(indexEntryJSON(accessScope: kidScope, ownerID: stray))
        XCTAssertEqual(scoped.migratedItem.ownerID, "plex|server-a|kid-uuid")

        let unusableScope = DownloadAccessScope(serverIdentifier: "", accessScopeIdentifier: "kid-uuid")
        let unusable = try indexEntry(indexEntryJSON(accessScope: unusableScope, ownerID: stray))
        XCTAssertNil(unusable.migratedItem.ownerID)
    }

    func test_indexEntryWithoutAccessScope_keepsTheOwnerIDItCarries() throws {
        // Only this app's fallback index carries an owner without a scope.
        let owned = try indexEntry(indexEntryJSON(ownerID: "plex|server-a|kid-uuid"))
        XCTAssertNil(owned.enrolledOwner)
        XCTAssertEqual(owned.migratedItem.ownerID, "plex|server-a|kid-uuid")

        let unowned = try indexEntry(indexEntryJSON())
        XCTAssertNil(unowned.migratedItem.ownerID)
    }

    func test_indexMigration_completeIndexIsLoadedAndPermitsTheOwnershipImport() throws {
        store("""
        {"unscoped": {"serverIdentifier": "server-a", "profileIdentifier": "kid-uuid"}}
        """)
        let indexURL = try writeIndex([
            indexEntryJSON(id: "scoped", ratingKey: "1", accessScope: kidScope),
            indexEntryJSON(id: "unscoped", ratingKey: "2"),
        ])
        let offlineStore = try makeStore()

        let state = LegacyDownloadIndex.migrate(indexFileURL: indexURL, into: offlineStore)

        XCTAssertEqual(state, .loaded)
        var items = try offlineStore.allDownloads()
        XCTAssertEqual(owner(of: "scoped", in: items), "plex|server-a|kid-uuid")
        XCTAssertNil(owner(of: "unscoped", in: items))
        XCTAssertTrue(items.allSatisfy { $0.enrichmentState == .pending })
        let kid = MediaOwner(server: indexServer, userID: "kid-uuid")
        XCTAssertEqual(offlineStore.owner(id: kid.id), kid)
        XCTAssertFalse(FileManager.default.fileExists(atPath: indexURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.appendingPathExtension("migrated").path))

        let outcome = LegacyDownloadOwnership.migrate(items, indexState: state, defaults: defaults) { items = $0 }

        XCTAssertEqual(outcome, .migrated(["unscoped": kid]))
        XCTAssertEqual(owner(of: "unscoped", in: items), kid.id)
    }

    func test_indexMigration_withADamagedEntry_dropsOnlyThatEntryAndDefersTheOwnershipImport() throws {
        store("""
        {"unscoped": {"serverIdentifier": "server-a", "profileIdentifier": "kid-uuid"}}
        """)
        let indexURL = try writeIndex([
            indexEntryJSON(id: "scoped", ratingKey: "1", accessScope: kidScope),
            #"{"id": "damaged", "status": "completed"}"#,
            indexEntryJSON(id: "unscoped", ratingKey: "2"),
        ])
        let offlineStore = try makeStore()

        let state = LegacyDownloadIndex.migrate(indexFileURL: indexURL, into: offlineStore)

        XCTAssertEqual(state, .corrupt)
        let items = try offlineStore.allDownloads()
        XCTAssertEqual(Set(items.map(\.id)), ["scoped", "unscoped"])
        XCTAssertEqual(owner(of: "scoped", in: items), "plex|server-a|kid-uuid")
        XCTAssertNil(owner(of: "unscoped", in: items))
        // The pre-fork file is moved aside with the damaged entry, never deleted.
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.appendingPathExtension("migrated").path))

        var saveCount = 0
        let outcome = LegacyDownloadOwnership.migrate(items, indexState: state, defaults: defaults) { _ in
            saveCount += 1
        }

        XCTAssertEqual(outcome, .deferred)
        XCTAssertEqual(saveCount, 0)
        XCTAssertNotNil(defaults.object(forKey: LegacyDownloadOwnership.defaultsKey))
    }

    func test_indexMigration_ofAFileThatIsNotAList_keepsItInPlace() throws {
        let indexURL = try writeIndex(raw: #"{"not": "a list"}"#)
        let offlineStore = try makeStore()

        XCTAssertEqual(LegacyDownloadIndex.migrate(indexFileURL: indexURL, into: offlineStore), .corrupt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path))
        XCTAssertTrue(try offlineStore.allDownloads().isEmpty)
    }

    // MARK: - Pre-fork offline resume points

    func test_indexMigration_movesThePreForkResumePointIntoTheOwnersOfflineProgress() throws {
        let playedAt = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let indexURL = try writeIndex([
            indexEntryJSON(
                id: "scoped", ratingKey: "1", accessScope: kidScope, viewOffset: "1234.5", lastPlayedAt: playedAt,
            ),
            indexEntryJSON(id: "unscoped", ratingKey: "2", viewOffset: "600", lastPlayedAt: playedAt),
        ])
        let offlineStore = try makeStore()
        XCTAssertEqual(LegacyDownloadIndex.migrate(indexFileURL: indexURL, into: offlineStore), .loaded)
        var items = try offlineStore.allDownloads()
        XCTAssertEqual(
            items.first { $0.id == "scoped" }?.metadata.legacyResumePoint,
            LegacyDownloadResumePoint(position: 1234.5, lastPlayedAt: playedAt),
        )

        XCTAssertTrue(LegacyDownloadIndex.restoreResumePoints(in: &items, store: offlineStore))

        let kid = MediaOwner(server: indexServer, userID: "kid-uuid")
        let watchState = try XCTUnwrap(offlineStore.watchState(itemID: "1", owner: kid))
        XCTAssertEqual(watchState.viewOffset, 1234.5)
        XCTAssertEqual(watchState.lastViewedAt, playedAt)
        XCTAssertEqual(watchState.source, .local)
        XCTAssertFalse(watchState.played)
        // Journaled like an interrupted stream, so the server is reconciled later, most recent wins.
        let journal = offlineStore.pendingJournal(owner: kid)
        XCTAssertEqual(journal.map(\.itemID), ["1"])
        XCTAssertEqual(journal.first?.event, ProgressJournalEvent.stop.rawValue)
        XCTAssertEqual(journal.first?.position, 1234.5)
        XCTAssertEqual(journal.first?.duration, 5400)
        XCTAssertEqual(journal.first?.occurredAt, playedAt)
        // The point is moved, not copied. A download without an owner keeps its point and records nothing.
        XCTAssertNil(items.first { $0.id == "scoped" }?.metadata.legacyResumePoint)
        XCTAssertEqual(items.first { $0.id == "unscoped" }?.metadata.legacyResumePoint?.position, 600)
        XCTAssertFalse(LegacyDownloadIndex.restoreResumePoints(in: &items, store: offlineStore))
        XCTAssertEqual(offlineStore.pendingJournal(owner: kid).count, 1)
    }

    func test_resumePointWaitsWithAnUnownedDownloadUntilTheOwnershipImportNamesItsOwner() throws {
        store("""
        {"unscoped": {"serverIdentifier": "server-a", "profileIdentifier": "kid-uuid"}}
        """)
        let playedAt = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let indexURL = try writeIndex([
            indexEntryJSON(id: "unscoped", ratingKey: "2", viewOffset: "600", lastPlayedAt: playedAt),
        ])
        let offlineStore = try makeStore()
        let state = LegacyDownloadIndex.migrate(indexFileURL: indexURL, into: offlineStore)
        var items = try offlineStore.allDownloads()
        XCTAssertFalse(LegacyDownloadIndex.restoreResumePoints(in: &items, store: offlineStore))

        let outcome = LegacyDownloadOwnership.migrate(items, indexState: state, defaults: defaults) { migrated in
            items = migrated
            try offlineStore.save(downloads: migrated)
        }
        let kid = MediaOwner(server: indexServer, userID: "kid-uuid")
        XCTAssertEqual(outcome, .migrated(["unscoped": kid]))
        // As `DownloadManager` does for every imported owner.
        offlineStore.register(owner: kid)
        // The point survived the offline database while the download had no owner.
        items = try offlineStore.allDownloads()

        XCTAssertTrue(LegacyDownloadIndex.restoreResumePoints(in: &items, store: offlineStore))
        XCTAssertEqual(offlineStore.watchState(itemID: "2", owner: kid)?.viewOffset, 600)
        XCTAssertEqual(offlineStore.pendingJournal(owner: kid).map(\.occurredAt), [playedAt])
    }

    func test_resumePoint_neverOverwritesMoreRecentProgress() throws {
        let offlineStore = try makeStore()
        let kid = MediaOwner(server: indexServer, userID: "kid-uuid")
        let newer = Date(timeIntervalSinceReferenceDate: 800_000_000)
        offlineStore.setWatchState(
            OfflineWatchState(viewOffset: 42, viewCount: 0, played: false, lastViewedAt: newer, source: .local),
            itemID: "123",
            owner: kid,
        )
        var item = try indexEntry(indexEntryJSON(
            accessScope: kidScope,
            viewOffset: "1234.5",
            lastPlayedAt: Date(timeIntervalSinceReferenceDate: 700_000_000),
        )).migratedItem

        LegacyDownloadIndex.restoreResumePoint(of: &item, owner: kid, store: offlineStore)

        XCTAssertNil(item.metadata.legacyResumePoint)
        XCTAssertEqual(offlineStore.watchState(itemID: "123", owner: kid)?.viewOffset, 42)
        XCTAssertEqual(offlineStore.watchState(itemID: "123", owner: kid)?.lastViewedAt, newer)
        XCTAssertTrue(offlineStore.pendingJournal(owner: kid).isEmpty)

        // Restoring the same point again, as after a failed save, records nothing twice, even though the offline
        // database reads the pre-fork date back only to the millisecond.
        let playedAt = Date(timeIntervalSinceReferenceDate: 900_000_000.123_456)
        let json = indexEntryJSON(accessScope: kidScope, viewOffset: "60", lastPlayedAt: playedAt)
        var first = try indexEntry(json).migratedItem
        var retried = try indexEntry(json).migratedItem
        LegacyDownloadIndex.restoreResumePoint(of: &first, owner: kid, store: offlineStore)
        LegacyDownloadIndex.restoreResumePoint(of: &retried, owner: kid, store: offlineStore)
        XCTAssertEqual(offlineStore.watchState(itemID: "123", owner: kid)?.viewOffset, 60)
        XCTAssertEqual(offlineStore.pendingJournal(owner: kid).count, 1)
    }

    func test_resumePointWithoutAPlayDate_countsAsPlayedWhenTheDownloadWasMade() throws {
        let offlineStore = try makeStore()
        let kid = MediaOwner(server: indexServer, userID: "kid-uuid")
        var item = try indexEntry(indexEntryJSON(accessScope: kidScope, viewOffset: "300")).migratedItem
        XCTAssertNil(item.metadata.legacyResumePoint?.lastPlayedAt)

        LegacyDownloadIndex.restoreResumePoint(of: &item, owner: kid, store: offlineStore)

        XCTAssertEqual(offlineStore.watchState(itemID: "123", owner: kid)?.lastViewedAt, item.metadata.createdAt)
        XCTAssertEqual(offlineStore.pendingJournal(owner: kid).map(\.occurredAt), [item.metadata.createdAt])
    }

    func test_resumePoint_onlyAPositivePositionIsKeptAndADamagedOneNeverCostsTheDownload() throws {
        for offset in ["0", "-5", #""12""#, "null"] {
            let entry = try indexEntry(indexEntryJSON(accessScope: kidScope, viewOffset: offset))

            XCTAssertNil(entry.item.metadata.legacyResumePoint, offset)
            XCTAssertEqual(entry.item.status, .completed, offset)
            XCTAssertEqual(entry.migratedItem.ownerID, "plex|server-a|kid-uuid", offset)
        }

        let damagedDate = try indexEntry(indexEntryJSON(
            viewOffset: "90",
            extraMetadata: #""lastPlayedAt": "yesterday""#,
        ))
        XCTAssertEqual(damagedDate.item.metadata.legacyResumePoint, LegacyDownloadResumePoint(position: 90))
    }

    // MARK: - Helpers

    private func store(_ json: String) {
        defaults.set(Data(json.utf8), forKey: LegacyDownloadOwnership.defaultsKey)
    }

    private func makeStore() throws -> OfflineStore {
        let database = try TestOfflineDatabase()
        offlineDatabase = database
        return database.makeStore()
    }

    private func indexEntry(_ json: String) throws -> LegacyDownloadIndexEntry {
        try JSONDecoder().decode(LegacyDownloadIndexEntry.self, from: Data(json.utf8))
    }

    private func writeIndex(_ entries: [String]) throws -> URL {
        try writeIndex(raw: "[\(entries.joined(separator: ","))]")
    }

    private func writeIndex(raw: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plinx.tests.index.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        indexDirectory = directory
        let url = directory.appendingPathComponent("index.json")
        try Data(raw.utf8).write(to: url)
        return url
    }

    /// One entry of `index.json` as pre-fork Plinx wrote it: the metadata names the item by `ratingKey` with no
    /// server, and the enrollment scope and offline resume point sit beside it.
    private func indexEntryJSON(
        id: String = "legacy",
        ratingKey: String = "123",
        accessScope: DownloadAccessScope? = nil,
        ownerID: String? = nil,
        storedServer: ServerIdentity? = nil,
        viewOffset: String? = nil,
        lastPlayedAt: Date? = nil,
        extraMetadata: String? = nil,
    ) -> String {
        var fields = [
            #""id": "\#(id)""#,
            #""status": "completed""#,
            #""progress": 1"#,
            #""bytesWritten": 1024"#,
            #""totalBytes": 1024"#,
            #""requestedQuality": "megabits3_720p""#,
        ]
        if let accessScope {
            let server = accessScope.serverIdentifier
            let profile = accessScope.accessScopeIdentifier
            fields.append(#""accessScope": {"serverIdentifier": "\#(server)", "accessScopeIdentifier": "\#(profile)"}"#)
        }
        if let ownerID {
            fields.append(#""ownerID": "\#(ownerID)""#)
        }
        var metadata = [
            #""ratingKey": "\#(ratingKey)""#,
            #""guid": "plex://movie/\#(ratingKey)""#,
            #""type": "movie""#,
            #""title": "Movie \#(ratingKey)""#,
            #""genres": []"#,
            #""duration": 5400"#,
            #""contentRating": "G""#,
            #""videoFileName": "video.mp4""#,
            #""createdAt": 1"#,
        ]
        if let storedServer {
            metadata.append(#""provider": "\#(storedServer.provider.rawValue)""#)
            metadata.append(#""serverIdentifier": "\#(storedServer.id)""#)
        }
        if let viewOffset {
            metadata.append(#""viewOffset": \#(viewOffset)"#)
        }
        if let lastPlayedAt {
            metadata.append(#""lastPlayedAt": \#(lastPlayedAt.timeIntervalSinceReferenceDate)"#)
        }
        if let extraMetadata {
            metadata.append(extraMetadata)
        }
        fields.append(#""metadata": {\#(metadata.joined(separator: ", "))}"#)
        return "{\(fields.joined(separator: ", "))}"
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
