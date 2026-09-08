import Foundation

/// The durable part of a successful Plinx session.  Deliberately excludes
/// auth tokens: those remain owned by SessionManager's Keychain entry.
struct OfflineSessionSnapshot: Codable, Equatable, Hashable {
    let identity: DownloadOwnerIdentity
    let serverName: String
    let profileName: String?
    let savedAt: Date

    init(identity: DownloadOwnerIdentity, serverName: String,
         profileName: String? = nil, savedAt: Date = Date())
    {
        self.identity = identity
        self.serverName = serverName
        self.profileName = profileName
        self.savedAt = savedAt
    }
}

protocol OfflineSessionPersistence {
    func load() throws -> OfflineSessionSnapshot?
    func save(_ snapshot: OfflineSessionSnapshot) throws
    func remove() throws
}

/// Keychain-backed persistence. A present but malformed value is an error,
/// allowing callers to fail closed instead of treating corruption as logout.
struct KeychainOfflineSessionPersistence: OfflineSessionPersistence {
    private let keychain: Keychain
    private let key: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.bballdavis.plinx",
         key: String = "plinx.offlineSession.v1")
    {
        keychain = Keychain(service: service)
        self.key = key
    }

    func load() throws -> OfflineSessionSnapshot? {
        guard let raw = try keychain.string(forKey: key) else { return nil }
        guard let data = raw.data(using: .utf8) else { throw OfflineSessionStoreError.corrupt }
        do { return try JSONDecoder().decode(OfflineSessionSnapshot.self, from: data) }
        catch { throw OfflineSessionStoreError.corrupt }
    }

    func save(_ snapshot: OfflineSessionSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try keychain.setString(String(decoding: data, as: UTF8.self), forKey: key)
    }

    func remove() throws {
        try keychain.deleteValue(forKey: key)
    }
}

enum OfflineSessionStoreError: Error, Equatable {
    case corrupt
}

/// Small in-memory implementation used by unit tests and deterministic UI
/// harnesses; it also documents the persistence contract.
final class InMemoryOfflineSessionPersistence: OfflineSessionPersistence {
    var snapshot: OfflineSessionSnapshot?
    var loadError: Error?
    var saveError: Error?
    init(snapshot: OfflineSessionSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func load() throws -> OfflineSessionSnapshot? {
        if let loadError {
            throw loadError
        }
        return snapshot
    }

    func save(_ snapshot: OfflineSessionSnapshot) throws {
        if let saveError {
            throw saveError
        }
        self.snapshot = snapshot
    }

    func remove() throws {
        snapshot = nil
    }
}
