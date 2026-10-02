import Foundation
import Security

protocol CredentialStore {
    func load(key: String) throws -> String?
    func save(key: String, value: String) throws
    func delete(key: String) throws
}

protocol KeychainAccess {
    func read(_ query: CFDictionary, result: inout CFTypeRef?) -> OSStatus
    func add(_ attributes: CFDictionary) -> OSStatus
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

struct SystemKeychainAccess: KeychainAccess {
    func read(_ query: CFDictionary, result: inout CFTypeRef?) -> OSStatus { SecItemCopyMatching(query, &result) }
    func add(_ attributes: CFDictionary) -> OSStatus { SecItemAdd(attributes, nil) }
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus { SecItemUpdate(query, attributes) }
    func delete(_ query: CFDictionary) -> OSStatus { SecItemDelete(query) }
}

/// Mutations always specify a service and account. For the two historical TypoFixr
/// accounts only, migrate pre-1.3.0 items whose service is explicitly empty.
struct KeychainStore: CredentialStore {
    static let shared = KeychainStore()
    let service: String
    private let access: any KeychainAccess

    init(service: String = AppHelpers.keychainService, access: any KeychainAccess = SystemKeychainAccess()) {
        self.service = service
        self.access = access
    }

    private func query(key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    func load(key: String) throws -> String? {
        if let value = try readValue(query(key: key)) { return value }
        guard let legacy = legacyQuery(key: key), let value = try readValue(legacy) else { return nil }
        // Only remove the exact legacy item after the scoped save succeeds.
        try save(key: key, value: value)
        try deleteItem(legacy)
        return value
    }

    private func readValue(_ query: [String: Any]) throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = access.read(query as CFDictionary, result: &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: errSecDecode)
        }
        return value
    }

    private func legacyQuery(key: String) -> [String: Any]? {
        guard service == AppHelpers.keychainService, ["groq_api_key", "device_id"].contains(key) else { return nil }
        var legacy = query(key: key)
        // Omitting the service would also match credentials belonging to other apps.
        legacy[kSecAttrService as String] = ""
        return legacy
    }

    func save(key: String, value: String) throws {
        let query = query(key: key)
        let attributes = [kSecValueData as String: Data(value.utf8)]
        let status = access.update(query as CFDictionary, attributes: attributes as CFDictionary)
        if status == errSecItemNotFound {
            try check(access.add(query.merging(attributes) { _, new in new } as CFDictionary))
        } else {
            try check(status)
        }
    }

    func delete(key: String) throws {
        try deleteItem(query(key: key))
        if let legacy = legacyQuery(key: key) { try deleteItem(legacy) }
    }

    private func deleteItem(_ query: [String: Any]) throws {
        let status = access.delete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Could not access saved credentials: \(SecCopyErrorMessageString(status, nil) as String? ?? String(status))"
        }
    }
}

/// Ephemeral credentials for isolated sessions, previews, and tests.
final class MemoryCredentialStore: CredentialStore {
    private var values: [String: String] = [:]
    func load(key: String) throws -> String? { values[key] }
    func save(key: String, value: String) throws { values[key] = value }
    func delete(key: String) throws { values.removeValue(forKey: key) }
}
