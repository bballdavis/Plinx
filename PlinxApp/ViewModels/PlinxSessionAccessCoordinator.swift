import Foundation
import Network
import Observation

enum PlinxSessionAccessState: Equatable {
    /// An enrolled family is connecting at launch. Downloads stay authorized,
    /// but the UI shows loading instead of an offline warning until the
    /// connection fails or the device reports no network.
    case hydrating
    case online
    case offline(OfflineSessionSnapshot)
    case signedOut
    case unavailable
}

@MainActor
@Observable
final class PlinxSessionAccessCoordinator {
    private(set) var state: PlinxSessionAccessState = .hydrating
    private(set) var snapshot: OfflineSessionSnapshot?
    private(set) var reconnectGeneration = 0
    private var reconnectTask: Task<Void, Never>?
    private let persistence: OfflineSessionPersistence

    init(persistence: OfflineSessionPersistence = KeychainOfflineSessionPersistence()) {
        self.persistence = persistence
        do {
            snapshot = try persistence.load()
            // Being enrolled is not evidence of being offline. Stay in the
            // launch connection state until hydration fails or the device has
            // no network path.
            state = snapshot == nil ? .signedOut : .hydrating
        } catch {
            snapshot = nil
            state = .unavailable
        }
    }

    var isLocallyEnrolled: Bool {
        snapshot != nil && state != .unavailable && state != .signedOut
    }

    /// True until the first launch connection succeeds or is known to fail.
    var isAwaitingInitialConnection: Bool {
        state == .hydrating
    }

    var isReconnecting: Bool {
        reconnectTask != nil
    }

    var effectiveDownloadIdentity: DownloadOwnerIdentity? {
        switch state {
        case .hydrating, .online, .offline: return snapshot?.identity
        case .signedOut, .unavailable: return nil
        }
    }

    func recordReadySession(sessionManager: SessionManager) {
        // Demo can be re-entered offline through its explicit connection action;
        // never replace a personal offline snapshot with the sample identity.
        guard sessionManager.plexServer?.clientIdentifier != DemoFixtureBootstrap.serverIdentifier else { return }
        guard sessionManager.status == .ready,
              let identity = sessionManager.plinxDownloadOwnerIdentity,
              let server = sessionManager.plexServer else { return }
        recordReady(identity: identity, serverName: server.name,
                    profileName: sessionManager.user?.friendlyName ?? sessionManager.user?.title)
    }

    func recordReady(identity: DownloadOwnerIdentity, serverName: String, profileName: String? = nil) {
        let next = OfflineSessionSnapshot(identity: identity, serverName: serverName,
                                          profileName: profileName)
        do {
            try persistence.save(next)
            snapshot = next
        } catch {
            // Never retain a prior profile's offline authorization when its
            // replacement could not be made durable. The live session remains
            // usable, but offline access fails closed until a later save.
            try? persistence.remove()
            snapshot = nil
        }
        state = .online
    }

    func markRemoteFailure() {
        guard let snapshot else { state = .signedOut; return }
        state = .offline(snapshot)
    }

    /// The device has no network path, so the launch connection cannot
    /// succeed. Show offline Downloads now instead of waiting for timeouts.
    func markNetworkUnavailable() {
        guard state == .hydrating else { return }
        markRemoteFailure()
    }

    /// Retries automatically when connectivity returns after a known failure.
    func networkBecameAvailable(_ operation: @escaping () async -> Bool) {
        guard case .offline = state else { return }
        reconnect(operation)
    }

    func markSignedOut() {
        reconnectGeneration += 1
        reconnectTask?.cancel()
        reconnectTask = nil
        do { try persistence.remove() } catch { /* local access is revoked in memory */ }
        snapshot = nil
        state = .signedOut
    }

    /// Starts at most one reconnect operation. A stale completion cannot
    /// restore online state after logout or a newer reconnect attempt.
    func reconnect(_ operation: @escaping () async -> Bool) {
        guard reconnectTask == nil, snapshot != nil else { return }
        reconnectGeneration += 1
        let generation = reconnectGeneration
        reconnectTask = Task { [weak self] in
            let succeeded = await operation()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.reconnectGeneration == generation else { return }
                self.reconnectTask = nil
                self.state = succeeded ? .online : (self.snapshot.map { .offline($0) } ?? .signedOut)
            }
        }
    }
}

extension PlinxSessionAccessCoordinator {
    func reconnect(using sessionManager: SessionManager) {
        reconnect { await sessionManager.hydrate(); return sessionManager.status == .ready }
    }

    func networkBecameAvailable(using sessionManager: SessionManager) {
        networkBecameAvailable { await sessionManager.hydrate(); return sessionManager.status == .ready }
    }
}

/// Reports whether the device currently has any usable network path.
/// `isSatisfied` is nil until the system delivers the first path.
@MainActor
@Observable
final class PlinxNetworkPathMonitor {
    private(set) var isSatisfied: Bool?
    @ObservationIgnored private var monitor: NWPathMonitor?

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.isSatisfied != satisfied else { return }
                self.isSatisfied = satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.bballdavis.plinx.network-path"))
        self.monitor = monitor
    }
}

extension SessionManager {
    func effectiveDownloadIdentity(using access: PlinxSessionAccessCoordinator?) -> DownloadOwnerIdentity? {
        plinxDownloadOwnerIdentity ?? access?.effectiveDownloadIdentity
    }

    func signOutRevokingLocalAccess(_ access: PlinxSessionAccessCoordinator) async {
        access.markSignedOut()
        await signOut()
    }
}
