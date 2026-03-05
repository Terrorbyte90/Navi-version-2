import Foundation
import Security

final class KeychainManager {
    static let shared = KeychainManager()

    private let service = Constants.Keychain.service
    private let accessGroup = Constants.Keychain.accessGroup

    private init() {}

    // MARK: - CRUD
    func save(key: String, value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Delete existing first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func get(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else {
            throw KeychainError.notFound(key)
        }

        return string
    }

    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    func exists(key: String) -> Bool {
        (try? get(key: key)) != nil
    }

    func listAll() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]]
        else { return [] }

        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    // MARK: - Convenience
    var anthropicAPIKey: String? {
        try? get(key: Constants.Keychain.anthropicKey)
    }

    func saveAnthropicKey(_ key: String) throws {
        try save(key: Constants.Keychain.anthropicKey, value: key)
    }

    var elevenLabsAPIKey: String? {
        try? get(key: Constants.Keychain.elevenLabsKey)
    }

    func saveElevenLabsKey(_ key: String) throws {
        try save(key: Constants.Keychain.elevenLabsKey, value: key)
    }

    func getKey(for service: String) -> String? {
        try? get(key: service)
    }

    func saveKey(_ value: String, for service: String) throws {
        try save(key: service, value: value)
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status): return "Keychain save failed: \(status)"
        case .notFound(let key): return "Key not found in keychain: \(key)"
        }
    }
}
