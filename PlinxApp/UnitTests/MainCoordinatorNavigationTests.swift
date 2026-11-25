import SwiftUI
import XCTest
@testable import Plinx

@MainActor
final class MainCoordinatorNavigationTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "MainCoordinatorNavigationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    private func makeCoordinator() -> MainCoordinator {
        MainCoordinator(settingsManager: SettingsManager(userDefaults: defaults))
    }

    func test_resetToRoot_clearsHomePath() {
        let coordinator = makeCoordinator()
        coordinator.homePath.append("detail")

        coordinator.resetToRoot(for: .home)

        XCTAssertEqual(coordinator.homePath.count, 0)
    }

    func test_resetToRoot_clearsLibraryPathForLibraryDetailTab() {
        let coordinator = makeCoordinator()
        coordinator.libraryPath.append("library-detail")
        let library = LibraryIdentity(
            server: ServerIdentity(provider: .plex, id: "server-1"),
            libraryID: "library-123"
        )

        coordinator.resetToRoot(for: .libraryDetail(library))

        XCTAssertEqual(coordinator.libraryPath.count, 0)
    }
}
