import Foundation
import Security

enum YoutarrStrings {
    static func value(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Plinx", bundle: .main, value: key, comment: "Youtarr settings")
    }
}

/// The validated, non-secret details needed to contact a family's Youtarr server.
struct YoutarrConfiguration: Equatable {
    let baseURL: URL
    let apiKey: String

    init(baseURL: URL, apiKey: String) throws {
        self.baseURL = try YoutarrURLPolicy.normalizedBaseURL(from: baseURL)
        self.apiKey = apiKey
    }

    func endpointURL(path: String) -> URL {
        baseURL.appendingPathComponent("external-api/v1", isDirectory: true)
            .appendingPathComponent(path)
    }
}

enum YoutarrConfigurationError: LocalizedError, Equatable {
    case invalidURL
    case missingAPIKey
    case credentialStoreUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return YoutarrStrings.value("youtarr.error.invalidURL")
        case .missingAPIKey:
            return YoutarrStrings.value("youtarr.error.missingAPIKey")
        case .credentialStoreUnavailable:
            return YoutarrStrings.value("youtarr.error.credentialStore")
        }
    }
}

enum YoutarrURLPolicy {
    static func normalizedBaseURL(from string: String) throws -> URL {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw YoutarrConfigurationError.invalidURL
        }
        return try normalizedBaseURL(from: url)
    }

    static func normalizedBaseURL(from url: URL) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              !url.absoluteString.contains("?"),
              !url.absoluteString.contains("#") else {
            throw YoutarrConfigurationError.invalidURL
        }

        if scheme == "http" && !isLocalNetworkHost(components.host!) {
            throw YoutarrConfigurationError.invalidURL
        }

        components.scheme = scheme
        components.path = normalizedPath(components.path)
        guard let normalized = components.url else {
            throw YoutarrConfigurationError.invalidURL
        }
        return normalized
    }

    private static func normalizedPath(_ path: String) -> String {
        var result = path
        while result.hasSuffix("/") { result.removeLast() }
        if result.hasSuffix("/external-api/v1") {
            result.removeLast("/external-api/v1".count)
        }
        return result.isEmpty ? "/" : result
    }

    private static func isLocalNetworkHost(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host.hasSuffix(".local") || host == "::1" {
            return true
        }
        if isPrivateIPv4(host) { return true }
        return isLocalIPv6(host)
    }

    private static func isPrivateIPv4(_ host: String) -> Bool {
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch octets[0] {
        case 10, 127: return true
        case 172: return (16...31).contains(octets[1])
        case 192: return octets[1] == 168
        default: return false
        }
    }

    private static func isLocalIPv6(_ host: String) -> Bool {
        guard host.contains(":"),
              let firstHextet = host.split(separator: ":", omittingEmptySubsequences: true).first,
              let value = Int(firstHextet, radix: 16) else { return false }
        // RFC 4193 unique-local fc00::/7 and RFC 4291 link-local fe80::/10.
        return (value & 0xfe00) == 0xfc00 || (value & 0xffc0) == 0xfe80
    }
}

protocol YoutarrCredentialStoring {
    func string(forKey key: String) throws -> String?
    func setString(_ value: String, forKey key: String) throws
    func deleteValue(forKey key: String) throws
}

/// Plinx-owned Keychain wrapper. Youtarr credentials never enter UserDefaults.
struct YoutarrKeychainCredentialStore: YoutarrCredentialStoring {
    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.bballdavis.plinx") {
        self.service = service
    }

    func string(forKey key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw YoutarrConfigurationError.credentialStoreUnavailable
        }
        return value
    }

    func setString(_ value: String, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw YoutarrConfigurationError.credentialStoreUnavailable
        }
        let addAttributes = query.merging(attributes) { $1 }
        guard SecItemAdd(addAttributes as CFDictionary, nil) == errSecSuccess else {
            throw YoutarrConfigurationError.credentialStoreUnavailable
        }
    }

    func deleteValue(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw YoutarrConfigurationError.credentialStoreUnavailable
        }
    }
}

struct YoutarrConfigurationStore {
    static let baseURLKey = "plinx.youtarr.baseURL"
    private static let apiKeyKey = "plinx.youtarr.apiKey"

    private let defaults: UserDefaults
    private let credentials: any YoutarrCredentialStoring

    init(
        defaults: UserDefaults = .standard,
        credentials: any YoutarrCredentialStoring = YoutarrKeychainCredentialStore()
    ) {
        self.defaults = defaults
        self.credentials = credentials
    }

    var storedBaseURL: String? { defaults.string(forKey: Self.baseURLKey) }

    func isConfigured() -> Bool {
        guard storedBaseURL?.isEmpty == false else { return false }
        return (try? credentials.string(forKey: Self.apiKeyKey))?.isEmpty == false
    }

    func load() throws -> YoutarrConfiguration? {
        guard let storedBaseURL, !storedBaseURL.isEmpty,
              let apiKey = try credentials.string(forKey: Self.apiKeyKey), !apiKey.isEmpty else {
            return nil
        }
        return try YoutarrConfiguration(baseURL: YoutarrURLPolicy.normalizedBaseURL(from: storedBaseURL), apiKey: apiKey)
    }

    /// Builds a candidate connection without modifying UserDefaults or Keychain.
    /// A blank key deliberately retains an existing secure credential.
    func draft(baseURL: String, apiKey: String) throws -> YoutarrConfiguration {
        let normalizedURL = try YoutarrURLPolicy.normalizedBaseURL(from: baseURL)
        let replacementKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let key: String
        if replacementKey.isEmpty {
            guard let existing = try credentials.string(forKey: Self.apiKeyKey), !existing.isEmpty else {
                throw YoutarrConfigurationError.missingAPIKey
            }
            key = existing
        } else {
            key = replacementKey
        }
        return try YoutarrConfiguration(baseURL: normalizedURL, apiKey: key)
    }

    @discardableResult
    func save(baseURL: String, apiKey: String) throws -> YoutarrConfiguration {
        let configuration = try draft(baseURL: baseURL, apiKey: apiKey)
        let replacementKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !replacementKey.isEmpty {
            try credentials.setString(replacementKey, forKey: Self.apiKeyKey)
        }
        defaults.set(configuration.baseURL.absoluteString, forKey: Self.baseURLKey)
        return configuration
    }

    func clear() throws {
        try credentials.deleteValue(forKey: Self.apiKeyKey)
        defaults.removeObject(forKey: Self.baseURLKey)
    }
}

enum YoutarrExplorePreference {
    static let storageKey = "plinx.youtarr.exploreEnabled"
    static let defaultEnabled = false
}

enum YoutarrExploreVisibility {
    static func shouldShow(isEnabled: Bool, isConfigured: Bool) -> Bool {
        isEnabled && isConfigured
    }
}
