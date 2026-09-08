@testable import Plinx
import XCTest

@MainActor
final class OfflineSessionAccessTests: XCTestCase {
    private let identity = DownloadOwnerIdentity(serverIdentifier: "server", profileIdentifier: "profile")

    func testMissingStoreStartsSignedOut() {
        let coordinator = PlinxSessionAccessCoordinator(persistence: InMemoryOfflineSessionPersistence())
        XCTAssertEqual(coordinator.state, .signedOut)
        XCTAssertNil(coordinator.effectiveDownloadIdentity)
    }

    func testEnrolledStoreLoadsOfflineIdentity() {
        let snapshot = OfflineSessionSnapshot(identity: identity, serverName: "Home")
        let coordinator = PlinxSessionAccessCoordinator(
            persistence: InMemoryOfflineSessionPersistence(snapshot: snapshot)
        )
        XCTAssertEqual(coordinator.state, .offline(snapshot))
        XCTAssertEqual(coordinator.effectiveDownloadIdentity, identity)
    }

    func testCorruptStoreFailsClosed() {
        let persistence = InMemoryOfflineSessionPersistence()
        persistence.loadError = OfflineSessionStoreError.corrupt
        let coordinator = PlinxSessionAccessCoordinator(persistence: persistence)
        XCTAssertEqual(coordinator.state, .unavailable)
        XCTAssertNil(coordinator.effectiveDownloadIdentity)
    }

    func testLiveReadyIdentityReplacesFallback() {
        let fallback = OfflineSessionSnapshot(identity: identity, serverName: "Old")
        let coordinator = PlinxSessionAccessCoordinator(
            persistence: InMemoryOfflineSessionPersistence(snapshot: fallback)
        )
        let live = DownloadOwnerIdentity(serverIdentifier: "new-server", profileIdentifier: "new-profile")
        coordinator.recordReady(identity: live, serverName: "New")
        XCTAssertEqual(coordinator.effectiveDownloadIdentity, live)
    }

    func testRevokeCancelsReconnectAndStalesCompletion() async {
        let coordinator = PlinxSessionAccessCoordinator(
            persistence: InMemoryOfflineSessionPersistence(snapshot: OfflineSessionSnapshot(identity: identity, serverName: "Home"))
        )
        let gate = AsyncGate()
        coordinator.reconnect { await gate.wait(); return true }
        coordinator.markSignedOut()
        await gate.open()
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(coordinator.state, .signedOut)
        XCTAssertNil(coordinator.effectiveDownloadIdentity)
    }

    func testReconnectIsSingleFlight() async {
        let coordinator = PlinxSessionAccessCoordinator(
            persistence: InMemoryOfflineSessionPersistence(snapshot: OfflineSessionSnapshot(identity: identity, serverName: "Home"))
        )
        let gate = AsyncGate()
        coordinator.reconnect { await gate.wait(); return true }
        coordinator.reconnect { XCTFail("second reconnect must not run"); return true }
        await gate.open()
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(coordinator.state, .online)
    }

    func testFailedSnapshotReplacementInvalidatesOldOfflineIdentity() {
        let fallback = OfflineSessionSnapshot(identity: identity, serverName: "Old")
        let persistence = InMemoryOfflineSessionPersistence(snapshot: fallback)
        persistence.saveError = OfflineSessionStoreError.corrupt
        let coordinator = PlinxSessionAccessCoordinator(persistence: persistence)
        let live = DownloadOwnerIdentity(serverIdentifier: "new-server", profileIdentifier: "new-profile")

        coordinator.recordReady(identity: live, serverName: "New")
        coordinator.markRemoteFailure()

        XCTAssertEqual(coordinator.state, .signedOut)
        XCTAssertNil(coordinator.effectiveDownloadIdentity)
        XCTAssertNil(persistence.snapshot)
    }

    func testProfileIdentityChangeReplacesFallbackBeforeRemoteFailure() {
        let profileA = OfflineSessionSnapshot(identity: identity, serverName: "Home")
        let persistence = InMemoryOfflineSessionPersistence(snapshot: profileA)
        let coordinator = PlinxSessionAccessCoordinator(persistence: persistence)
        let profileB = DownloadOwnerIdentity(serverIdentifier: "server", profileIdentifier: "profile-b")

        coordinator.recordReady(identity: profileB, serverName: "Home")
        coordinator.markRemoteFailure()

        XCTAssertEqual(coordinator.effectiveDownloadIdentity, profileB)
        XCTAssertEqual(persistence.snapshot?.identity, profileB)
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen {
            return
        }; await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true; waiters.forEach { $0.resume() }; waiters.removeAll()
    }
}
