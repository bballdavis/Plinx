import XCTest
@testable import Plinx

@MainActor
final class MainCoordinatorNavigationTests: XCTestCase {

    func test_resetToRoot_clearsHomePath() {
        let coordinator = MainCoordinator()
        coordinator.homePath.append("detail")

        coordinator.resetToRoot(for: .home)

        XCTAssertEqual(coordinator.homePath.count, 0)
    }

    func test_resetToRoot_clearsLibraryPathForLibraryDetailTab() {
        let coordinator = MainCoordinator()
        coordinator.libraryPath.append("library-detail")

        coordinator.resetToRoot(for: .libraryDetail("library-123"))

        XCTAssertEqual(coordinator.libraryPath.count, 0)
    }
}
