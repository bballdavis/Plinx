@testable import Plinx
import XCTest

/// Home screen settings (`plinx.homeHiddenLibraryIds`, `plinx.homeLibraryOrder`) stored plain library ids before
/// multi-server. `HomeLibrarySettingKeys.migrated` rewrites an id to its library's stable key only when exactly one
/// loaded library has that id, so a setting is never moved to a library on the wrong server.
final class HomeLibrarySettingKeysTests: XCTestCase {
    private let serverA = ServerIdentity(provider: .plex, id: "server-a")
    private let serverB = ServerIdentity(provider: .plex, id: "server-b")
    private let jellyfin = ServerIdentity(provider: .jellyfin, id: "server-j")

    func test_uniquePlainIdBecomesTheStableKeyOfItsLibrary() {
        let movies = library("1", on: serverA)
        let shows = library("2", on: serverA)

        let migrated = HomeLibrarySettingKeys.migrated(["2", "1"], libraries: [movies, shows])

        XCTAssertEqual(migrated, ["plex:server-a:2", "plex:server-a:1"], "Order is kept.")
        XCTAssertEqual(HomeLibrarySettingKeys.key(for: movies), "plex:server-a:1")
    }

    func test_ambiguousPlainIdIsKeptAsStored() {
        let libraries = [library("1", on: serverA), library("1", on: serverB)]

        XCTAssertEqual(HomeLibrarySettingKeys.migrated(["1"], libraries: libraries), ["1"])
    }

    func test_unmatchedPlainIdIsKeptAsStored() {
        let libraries = [library("1", on: serverA)]

        XCTAssertEqual(HomeLibrarySettingKeys.migrated(["7"], libraries: libraries), ["7"])
        XCTAssertEqual(HomeLibrarySettingKeys.migrated(["7"], libraries: []), ["7"])
    }

    func test_duplicatesAreDroppedAfterMigration() {
        let libraries = [library("1", on: serverA), library("abc", on: jellyfin)]

        let migrated = HomeLibrarySettingKeys.migrated(
            ["1", "plex:server-a:1", "abc", "abc", "9", "9"],
            libraries: libraries,
        )

        XCTAssertEqual(migrated, ["plex:server-a:1", "jellyfin:server-j:abc", "9"])
    }

    func test_stableKeysAreLeftAlone() {
        let libraries = [library("1", on: serverA)]
        // Already migrated, and one for a server that is not loaded: neither is touched.
        let stored = ["plex:server-a:1", "plex:server-gone:4"]

        let migrated = HomeLibrarySettingKeys.migrated(stored, libraries: libraries)

        XCTAssertEqual(migrated, stored)
        XCTAssertEqual(HomeLibrarySettingKeys.migrated(migrated, libraries: libraries), stored, "Idempotent.")
    }

    func test_keysForALibraryAcceptBothStoredForms() {
        let movies = library("1", on: serverA)

        let keys = HomeLibrarySettingKeys.keys(for: movies)

        XCTAssertEqual(keys.first, "plex:server-a:1", "The stable key is written; the plain id is only read.")
        XCTAssertTrue(keys.contains("1"))
    }

    private func library(_ id: String, on server: ServerIdentity) -> Library {
        Library(id: id, title: "Library \(id)", type: .movie, server: server)
    }
}
