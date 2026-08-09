import XCTest
@testable import Plinx

@MainActor
final class PlaybackLaunchCoordinatorTests: XCTestCase {

    func test_launchIgnoresRepeatedTapWhilePreparationIsPending() async {
        let coordinator = PlaybackLaunchCoordinator()
        var operationCount = 0

        coordinator.launch {
            operationCount += 1
            try? await Task.sleep(nanoseconds: 20_000_000)
            return .started
        }
        await Task.yield()

        coordinator.launch {
            operationCount += 1
            return .failed
        }

        XCTAssertTrue(coordinator.isLaunching)
        XCTAssertEqual(operationCount, 1)

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(coordinator.isLaunching)
        XCTAssertEqual(operationCount, 1)
        XCTAssertEqual(coordinator.lastResult, .started)
    }

    func test_cancelPendingLaunchClearsPresentationAndSuppressesLateResult() async {
        let coordinator = PlaybackLaunchCoordinator()

        coordinator.launch {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return .started
        }

        XCTAssertTrue(coordinator.isLaunching)
        coordinator.cancelPendingLaunch()
        await Task.yield()

        XCTAssertFalse(coordinator.isLaunching)
        XCTAssertNil(coordinator.lastResult)
    }
}
