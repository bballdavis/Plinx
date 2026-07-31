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
    let additionalHeader: YoutarrAdditionalHeader?

    init(
        baseURL: URL,
        apiKey: String,
        additionalHeader: YoutarrAdditionalHeader? = nil
    ) throws {
        self.baseURL = try YoutarrURLPolicy.normalizedBaseURL(from: baseURL)
        self.apiKey = apiKey
        self.additionalHeader = additionalHeader
    }

    func endpointURL(path: String) -> URL {
        baseURL.appendingPathComponent("external-api/v1", isDirectory: true)
            .appendingPathComponent(path)
    }
}

struct YoutarrAdditionalHeader: Codable, Equatable {
    let name: String
    let value: String

    init(name: String, value: String) throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, !normalizedValue.isEmpty else {
            throw YoutarrConfigurationError.missingAdditionalHeader
        }
        guard Self.isValidName(normalizedName),
              !Self.reservedNames.contains(normalizedName.lowercased()),
              !normalizedValue.contains("\r"),
              !normalizedValue.contains("\n") else {
            throw YoutarrConfigurationError.invalidAdditionalHeader
        }
        self.name = normalizedName
        self.value = normalizedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            name: container.decode(String.self, forKey: .name),
            value: container.decode(String.self, forKey: .value)
        )
    }

    private static let reservedNames: Set<String> = [
        "accept",
        "content-length",
        "content-type",
        "host",
        "x-api-key",
    ]

    private static func isValidName(_ name: String) -> Bool {
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~"
        )
        return name.unicodeScalars.allSatisfy(allowed.contains)
    }
}

enum YoutarrConfigurationError: LocalizedError, Equatable {
    case invalidURL
    case missingAPIKey
    case missingAdditionalHeader
    case invalidAdditionalHeader
    case credentialStoreUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return YoutarrStrings.value("youtarr.error.invalidURL")
        case .missingAPIKey:
            return YoutarrStrings.value("youtarr.error.missingAPIKey")
        case .missingAdditionalHeader:
            return YoutarrStrings.value("youtarr.error.missingAdditionalHeader")
        case .invalidAdditionalHeader:
            return YoutarrStrings.value("youtarr.error.invalidAdditionalHeader")
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
    private static let additionalHeaderKey = "plinx.youtarr.additionalHeader"

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

    func hasStoredAPIKey() -> Bool {
        (try? credentials.string(forKey: Self.apiKeyKey))?.isEmpty == false
    }

    func storedAdditionalHeaderName() throws -> String? {
        try storedAdditionalHeader()?.name
    }

    func hasStoredAdditionalHeader() -> Bool {
        (try? storedAdditionalHeader()) != nil
    }

    func isConfigured() -> Bool {
        guard storedBaseURL?.isEmpty == false else { return false }
        return hasStoredAPIKey()
    }

    func load() throws -> YoutarrConfiguration? {
        guard let storedBaseURL, !storedBaseURL.isEmpty,
              let apiKey = try credentials.string(forKey: Self.apiKeyKey), !apiKey.isEmpty else {
            return nil
        }
        return try YoutarrConfiguration(
            baseURL: YoutarrURLPolicy.normalizedBaseURL(from: storedBaseURL),
            apiKey: apiKey,
            additionalHeader: try storedAdditionalHeader()
        )
    }

    /// Builds a candidate connection without modifying UserDefaults or Keychain.
    /// Blank secret fields deliberately retain matching existing credentials.
    func draft(
        baseURL: String,
        apiKey: String,
        additionalHeaderEnabled: Bool = false,
        additionalHeaderName: String = "",
        additionalHeaderValue: String = ""
    ) throws -> YoutarrConfiguration {
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

        let additionalHeader: YoutarrAdditionalHeader?
        if additionalHeaderEnabled {
            let replacementName = additionalHeaderName.trimmingCharacters(in: .whitespacesAndNewlines)
            let replacementValue = additionalHeaderValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if replacementValue.isEmpty, let existing = try storedAdditionalHeader() {
                guard replacementName.isEmpty
                        || replacementName.caseInsensitiveCompare(existing.name) == .orderedSame else {
                    throw YoutarrConfigurationError.missingAdditionalHeader
                }
                additionalHeader = existing
            } else {
                additionalHeader = try YoutarrAdditionalHeader(
                    name: replacementName,
                    value: replacementValue
                )
            }
        } else {
            additionalHeader = nil
        }
        return try YoutarrConfiguration(
            baseURL: normalizedURL,
            apiKey: key,
            additionalHeader: additionalHeader
        )
    }

    @discardableResult
    func save(
        baseURL: String,
        apiKey: String,
        additionalHeaderEnabled: Bool = false,
        additionalHeaderName: String = "",
        additionalHeaderValue: String = ""
    ) throws -> YoutarrConfiguration {
        let configuration = try draft(
            baseURL: baseURL,
            apiKey: apiKey,
            additionalHeaderEnabled: additionalHeaderEnabled,
            additionalHeaderName: additionalHeaderName,
            additionalHeaderValue: additionalHeaderValue
        )
        let replacementKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !replacementKey.isEmpty {
            try credentials.setString(replacementKey, forKey: Self.apiKeyKey)
        }
        if let additionalHeader = configuration.additionalHeader {
            let data = try JSONEncoder().encode(additionalHeader)
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw YoutarrConfigurationError.credentialStoreUnavailable
            }
            try credentials.setString(encoded, forKey: Self.additionalHeaderKey)
        } else {
            try credentials.deleteValue(forKey: Self.additionalHeaderKey)
        }
        defaults.set(configuration.baseURL.absoluteString, forKey: Self.baseURLKey)
        return configuration
    }

    func clear() throws {
        try credentials.deleteValue(forKey: Self.apiKeyKey)
        try credentials.deleteValue(forKey: Self.additionalHeaderKey)
        defaults.removeObject(forKey: Self.baseURLKey)
    }

    private func storedAdditionalHeader() throws -> YoutarrAdditionalHeader? {
        guard let encoded = try credentials.string(forKey: Self.additionalHeaderKey),
              !encoded.isEmpty,
              let data = encoded.data(using: .utf8) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(YoutarrAdditionalHeader.self, from: data)
        } catch {
            throw YoutarrConfigurationError.credentialStoreUnavailable
        }
    }
}

enum YoutarrExplorePreference {
    static let storageKey = "plinx.youtarr.exploreEnabled"
    static let defaultEnabled = false
}

enum YoutarrRecommendationPreference {
    static let storageKey = "plinx.youtarr.recommendationsEnabled"
    static let defaultEnabled = false
}

enum YoutarrExploreVisibility {
    static func shouldShow(isEnabled: Bool, isConfigured: Bool) -> Bool {
        isEnabled && isConfigured
    }
}
