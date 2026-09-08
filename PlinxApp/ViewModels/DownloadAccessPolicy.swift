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
    private(set) var grandfatheredLegacyDownloadIDs: Set<String>
    private(set) var unprovenancedDownloadIDs: Set<String>
    private(set) var loadState: LoadState

    enum LoadState: Equatable { case loaded, migrated, unavailable, corrupt }
    private struct Envelope: Codable {
        var version: Int
        var owned: [String: DownloadOwnerIdentity]
        var grandfatheredLegacy: [String]
        var unprovenanced: [String]
    }

    private let defaults: UserDefaults
    private let storageKey = "plinx.downloadOwnership.v1"

    init(
        defaults: UserDefaults = .standard,
        existingDownloadItems: [DownloadItem] = [],
        canMigrateExistingDownloads: Bool = true
    ) {
        self.defaults = defaults
        grandfatheredLegacyDownloadIDs = []
        unprovenancedDownloadIDs = []
        loadState = .loaded
        guard let data = defaults.data(forKey: storageKey) else {
            identitiesByDownloadID = [:]
            guard canMigrateExistingDownloads else {
                loadState = .unavailable
                return
            }
            grandfatheredLegacyDownloadIDs = Set(existingDownloadItems.map(\.id))
            if !grandfatheredLegacyDownloadIDs.isEmpty {
                loadState = .migrated; persist()
            }
            return
        }
        do {
            if let decoded = try? JSONDecoder().decode(Envelope.self, from: data), decoded.version == 2 {
                identitiesByDownloadID = decoded.owned
                grandfatheredLegacyDownloadIDs = Set(decoded.grandfatheredLegacy)
                unprovenancedDownloadIDs = Set(decoded.unprovenanced)
            } else if let legacy = try? JSONDecoder().decode([String: DownloadOwnerIdentity].self, from: data) {
                identitiesByDownloadID = legacy
                guard canMigrateExistingDownloads else {
                    loadState = .unavailable
                    return
                }
                grandfatheredLegacyDownloadIDs = Set(existingDownloadItems.map(\.id)).subtracting(legacy.keys)
                loadState = .migrated
                persist()
            } else {
                throw CocoaError(.coderReadCorrupt)
            }
        } catch {
            identitiesByDownloadID = [:]
            grandfatheredLegacyDownloadIDs = []
            unprovenancedDownloadIDs = []
            loadState = .corrupt
        }
    }

    func identity(for downloadID: String) -> DownloadOwnerIdentity? {
        identitiesByDownloadID[downloadID]
    }

    func downloadIDs(ownedBy identity: DownloadOwnerIdentity) -> Set<String> {
        Set(identitiesByDownloadID.compactMap { downloadID, owner in
            owner == identity ? downloadID : nil
        })
    }

    func claim(downloadIDs: [String], as identity: DownloadOwnerIdentity) {
        guard loadState == .loaded || loadState == .migrated else { return }
        for downloadID in downloadIDs {
            identitiesByDownloadID[downloadID] = identity
        }
        grandfatheredLegacyDownloadIDs.subtract(downloadIDs)
        unprovenancedDownloadIDs.subtract(downloadIDs)
        persist()
    }

    func claimOrThrow(downloadIDs: [String], as identity: DownloadOwnerIdentity) throws {
        guard loadState == .loaded || loadState == .migrated else {
            throw DownloadOwnershipError.storeUnreadable
        }
        for downloadID in downloadIDs {
            identitiesByDownloadID[downloadID] = identity
        }
        grandfatheredLegacyDownloadIDs.subtract(downloadIDs)
        unprovenancedDownloadIDs.subtract(downloadIDs)
        try persistOrThrow()
    }

    func enroll(_ downloadID: String, as identity: DownloadOwnerIdentity) throws {
        guard loadState == .loaded || loadState == .migrated else {
            throw DownloadOwnershipError.storeUnreadable
        }
        identitiesByDownloadID[downloadID] = identity
        grandfatheredLegacyDownloadIDs.remove(downloadID)
        unprovenancedDownloadIDs.remove(downloadID)
        try persistOrThrow()
    }

    func removeEnrollment(_ downloadID: String, expectedIdentity: DownloadOwnerIdentity) throws {
        guard loadState == .loaded || loadState == .migrated else {
            throw DownloadOwnershipError.storeUnreadable
        }
        guard identitiesByDownloadID[downloadID] == expectedIdentity else { return }
        identitiesByDownloadID.removeValue(forKey: downloadID)
        try persistOrThrow()
    }

    func prune(keeping downloadIDs: Set<String>) {
        guard loadState == .loaded || loadState == .migrated else { return }
        let previousOwned = identitiesByDownloadID
        let previousLegacy = grandfatheredLegacyDownloadIDs
        let previousUnprovenanced = unprovenancedDownloadIDs
        identitiesByDownloadID = identitiesByDownloadID.filter {
            downloadIDs.contains($0.key)
        }
        grandfatheredLegacyDownloadIDs.formIntersection(downloadIDs)
        unprovenancedDownloadIDs.formIntersection(downloadIDs)
        if identitiesByDownloadID != previousOwned
            || grandfatheredLegacyDownloadIDs != previousLegacy
            || unprovenancedDownloadIDs != previousUnprovenanced
        {
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(Envelope(version: 2, owned: identitiesByDownloadID,
                                                            grandfatheredLegacy: Array(grandfatheredLegacyDownloadIDs), unprovenanced: Array(unprovenancedDownloadIDs))) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func persistOrThrow() throws {
        let data = try JSONEncoder().encode(Envelope(version: 2, owned: identitiesByDownloadID,
                                                     grandfatheredLegacy: Array(grandfatheredLegacyDownloadIDs), unprovenanced: Array(unprovenancedDownloadIDs)))
        defaults.set(data, forKey: storageKey)
    }
}

enum DownloadOwnershipError: Error { case storeUnreadable }

enum PlinxDownloadEnrollmentError: Error {
    case blockedByContentPolicy
    case authorizationChanged
}

enum PlinxDownloadEnrollmentAuthorization {
    static func permits(
        capturedIdentity: DownloadOwnerIdentity,
        liveIdentity: DownloadOwnerIdentity?
    ) -> Bool {
        liveIdentity == capturedIdentity
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

    func decision(for item: DownloadItem) -> DownloadAccessDecision {
        guard PlinxContentAuthorization.isAllowed(item.metadata.localMediaItem, policy: safetyPolicy) else {
            return .blockedByContentPolicy
        }

        guard let owner = ownershipStore.identity(for: item.id) else {
            return ownershipStore.grandfatheredLegacyDownloadIDs.contains(item.id) ? .allowed : .missingOwner
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

extension DownloadManager {
    func configurePlinxEnrollment(
        identity: DownloadOwnerIdentity?,
        safetyPolicy: SafetyPolicy,
        ownershipStore: DownloadOwnershipStore,
        sessionManager: SessionManager
    ) {
        configureEnrollmentContextProvider {
            guard let identity else { return nil }
            let scope = DownloadAccessScope(
                serverIdentifier: identity.serverIdentifier,
                accessScopeIdentifier: identity.profileIdentifier
            )
            return DownloadEnrollmentContext(
                scope: scope,
                authorizeAndEnroll: { downloadID, metadata in
                    guard PlinxDownloadEnrollmentAuthorization.permits(
                        capturedIdentity: identity,
                        liveIdentity: sessionManager.plinxDownloadOwnerIdentity
                    ) else {
                        throw PlinxDownloadEnrollmentError.authorizationChanged
                    }
                    guard PlinxContentAuthorization.isAllowed(
                        metadata.localMediaItem,
                        policy: safetyPolicy
                    ) else {
                        throw PlinxDownloadEnrollmentError.blockedByContentPolicy
                    }
                    try ownershipStore.enroll(downloadID, as: identity)
                },
                rollbackEnrollment: { downloadID in
                    try ownershipStore.removeEnrollment(downloadID, expectedIdentity: identity)
                }
            )
        }
    }
}
