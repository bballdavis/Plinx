#if !os(tvOS)
import Foundation

/// One-time import of the ownership record pre-fork Plinx kept beside its downloads, so families keep their kids'
/// downloads when they update.
///
/// Pre-fork Plinx stored, in UserDefaults under `plinx.downloadOwnership.v1`, the Plex server (machine identifier)
/// and the profile (Plex Home user UUID) each download was made for. That pair is a Plex `MediaOwner`, so a download
/// the record names gets that owner. Everything else stays unowned, which is parent-only (fail closed):
/// - "grandfathered" downloads, made before per-profile downloads. Pre-fork Plinx showed them to every profile,
///   signed in or not; one owner per download cannot express that, and giving them to one profile would be a guess;
/// - "unprovenanced" downloads, and downloads the record does not name;
/// - every download, when the record cannot be decoded. The record is then kept for recovery;
/// - every download, when the download list did not load completely. The record is then kept as well.
///
/// A download that already has an owner keeps it, and one whose stored server differs from the recorded one is left
/// alone. Ownership only decides whose downloads a profile sees: the content gate still checks each download when it
/// is listed and played.
enum LegacyDownloadOwnership {
    static let defaultsKey = "plinx.downloadOwnership.v1"

    enum Outcome: Equatable {
        /// The download list did not load completely: nothing changed and any record is kept.
        case deferred
        /// No record: nothing to import (a fresh install, or the import already ran).
        case nothingStored
        /// The record could not be decoded: nothing changed and the record is kept.
        case unreadable
        /// Saving the new owners failed: nothing changed and the record is kept for the next launch.
        case saveFailed
        /// The owners were saved (download id to its new owner) and the record removed.
        case migrated([String: MediaOwner])
    }

    /// Assigns the recorded owners, saves them with `save`, and only then removes the record.
    /// - Parameters:
    ///   - indexState: How the download list loaded. Only a complete list is migrated, so the record is never
    ///     consumed while some of the downloads it names still wait for recovery.
    ///   - save: Persists the updated downloads; when it throws, the record is kept.
    @MainActor
    static func migrate(
        _ items: [DownloadItem],
        indexState: DownloadPersistedIndexState,
        defaults: UserDefaults,
        save: ([DownloadItem]) throws -> Void,
    ) -> Outcome {
        guard indexState.permitsOwnershipMigration else { return .deferred }
        guard let stored = defaults.object(forKey: defaultsKey) else { return .nothingStored }
        guard let data = stored as? Data, let owners = recordedOwners(from: data) else { return .unreadable }
        let (migrated, assigned) = assigningOwners(owners, to: items)
        if !assigned.isEmpty {
            do {
                try save(migrated)
            } catch {
                return .saveFailed
            }
        }
        defaults.removeObject(forKey: defaultsKey)
        return .migrated(assigned)
    }

    /// The owner recorded for each download id, or nil when the record is not one pre-fork Plinx wrote.
    ///
    /// Version 2 is an envelope `{version, owned, grandfatheredLegacy, unprovenanced}`; only `owned` names owners.
    /// The first version was the bare `owned` dictionary. Entries with an empty server or profile are skipped.
    static func recordedOwners(from data: Data) -> [String: MediaOwner]? {
        let decoder = JSONDecoder()
        let owned: [String: RecordedOwner]
        if let envelope = try? decoder.decode(Envelope.self, from: data), envelope.version == 2 {
            owned = envelope.owned
        } else if let legacy = try? decoder.decode([String: RecordedOwner].self, from: data) {
            owned = legacy
        } else {
            return nil
        }
        return owned.compactMapValues(\.owner)
    }

    /// The downloads with the recorded owners assigned, and which downloads got one.
    static func assigningOwners(
        _ owners: [String: MediaOwner],
        to items: [DownloadItem],
    ) -> (items: [DownloadItem], assigned: [String: MediaOwner]) {
        var migrated = items
        var assigned: [String: MediaOwner] = [:]
        for index in migrated.indices where migrated[index].ownerID == nil {
            guard let owner = owners[migrated[index].id] else { continue }
            if let server = migrated[index].identity?.server {
                guard server == owner.server else { continue }
            } else {
                // Pre-fork downloads did not store their server; the record names it.
                migrated[index].metadata.identity = MediaIdentity(server: owner.server, itemID: migrated[index].itemID)
            }
            migrated[index].ownerID = owner.id
            assigned[migrated[index].id] = owner
        }
        return (migrated, assigned)
    }

    // MARK: - Pre-fork record

    /// `DownloadOwnerIdentity` of pre-fork Plinx.
    private struct RecordedOwner: Decodable {
        let serverIdentifier: String
        let profileIdentifier: String

        /// Pre-fork Plinx only ever enrolled Plex downloads, for the Plex Home user's UUID, which is the user id of
        /// a Plex `MediaOwner`.
        var owner: MediaOwner? {
            guard !serverIdentifier.isEmpty, !profileIdentifier.isEmpty else { return nil }
            return MediaOwner(
                server: ServerIdentity(provider: .plex, id: serverIdentifier),
                userID: profileIdentifier,
            )
        }
    }

    private struct Envelope: Decodable {
        let version: Int
        let owned: [String: RecordedOwner]
        let grandfatheredLegacy: [String]
        let unprovenanced: [String]
    }
}
#endif
