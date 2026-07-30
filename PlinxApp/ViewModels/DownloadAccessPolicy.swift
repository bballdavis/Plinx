import Foundation
import Observation
import PlinxCore

struct DownloadOwnerIdentity: Codable, Hashable {
    let serverIdentifier: String
    let profileIdentifier: String
}

@MainActor
@Observable
final class DownloadOwnershipStore {
    private(set) var identitiesByDownloadID: [String: DownloadOwnerIdentity]

    private let defaults: UserDefaults
    private let storageKey = "plinx.downloadOwnership.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(
               [String: DownloadOwnerIdentity].self,
               from: data
           ) {
            identitiesByDownloadID = decoded
        } else {
            identitiesByDownloadID = [:]
        }
    }

    func identity(for downloadID: String) -> DownloadOwnerIdentity? {
        identitiesByDownloadID[downloadID]
    }

    func claim(downloadIDs: [String], as identity: DownloadOwnerIdentity) {
        for downloadID in downloadIDs {
            identitiesByDownloadID[downloadID] = identity
        }
        persist()
    }

    func prune(keeping downloadIDs: Set<String>) {
        let previousCount = identitiesByDownloadID.count
        identitiesByDownloadID = identitiesByDownloadID.filter {
            downloadIDs.contains($0.key)
        }
        if identitiesByDownloadID.count != previousCount {
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(identitiesByDownloadID) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

enum DownloadAccessDecision: Equatable {
    case allowed
    case blockedByContentPolicy
    case wrongOwner
    case missingOwner
}

@MainActor
struct DownloadAccessPolicy {
    let safetyPolicy: SafetyPolicy
    let currentIdentity: DownloadOwnerIdentity?
    let ownershipStore: DownloadOwnershipStore

    init(
        safetyPolicy: SafetyPolicy,
        currentIdentity: DownloadOwnerIdentity?,
        ownershipStore: DownloadOwnershipStore
    ) {
        self.safetyPolicy = safetyPolicy
        self.currentIdentity = currentIdentity
        self.ownershipStore = ownershipStore
    }

    func decision(for item: DownloadItem) -> DownloadAccessDecision {
        guard PlinxContentAuthorization.isAllowed(item.metadata.localMediaItem, policy: safetyPolicy) else {
            return .blockedByContentPolicy
        }

        guard let owner = ownershipStore.identity(for: item.id) else {
            // Downloads created before Plinx began storing an owner cannot be
            // attributed safely to a historical profile. Treat them as shared
            // legacy media, while continuing to enforce the active rating
            // policy above. New downloads are claimed when they are enqueued.
            return .allowed
        }
        guard let currentIdentity, owner == currentIdentity else {
            return .wrongOwner
        }
        return .allowed
    }

    func filter(_ items: [DownloadItem]) -> [DownloadItem] {
        items.filter { decision(for: $0) == .allowed }
    }
}

extension SessionManager {
    var plinxDownloadOwnerIdentity: DownloadOwnerIdentity? {
        guard let serverIdentifier = plexServer?.clientIdentifier else { return nil }
        let profileIdentifier = user?.uuid
            ?? user?.id.map(String.init)
            ?? user?.username
        guard let profileIdentifier, !profileIdentifier.isEmpty else { return nil }
        return DownloadOwnerIdentity(
            serverIdentifier: serverIdentifier,
            profileIdentifier: profileIdentifier
        )
    }
}
