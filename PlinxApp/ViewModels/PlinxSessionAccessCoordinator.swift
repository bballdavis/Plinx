import Foundation
import Observation

enum PlinxSessionAccessState: Equatable {
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
            state = snapshot.map { .offline($0) } ?? .signedOut
        } catch {
            snapshot = nil
            state = .unavailable
        }
    }

    var isLocallyEnrolled: Bool {
        snapshot != nil && state != .unavailable && state != .signedOut
    }

    var effectiveDownloadIdentity: DownloadOwnerIdentity? {
        switch state {
        case .online: return snapshot?.identity
        case .offline: return snapshot?.identity
        default: return nil
        }
    }

    func recordReadySession(sessionManager: SessionManager) {
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

extension SessionManager {
    func effectiveDownloadIdentity(using access: PlinxSessionAccessCoordinator?) -> DownloadOwnerIdentity? {
        plinxDownloadOwnerIdentity ?? access?.effectiveDownloadIdentity
    }

    func signOutRevokingLocalAccess(_ access: PlinxSessionAccessCoordinator) async {
        access.markSignedOut()
        await signOut()
    }
}
