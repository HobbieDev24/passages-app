import Foundation
import Security
import LocalAuthentication

enum KeychainStore {
    private static let queue = DispatchQueue(label: "com.passages.keychain", qos: .userInitiated)

    static func loadNotionKey() async throws -> String { try await perform { try load() } }
    static func saveNotionKey(_ value: String) async throws { try await perform { try save(value) } }
    static func deleteNotionKey() async throws { try await perform { try delete() } }

    private static func perform<Value: Sendable>(_ operation: @escaping @Sendable () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try operation()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static var service: String { AppStorage.domain }
    // Keep the existing item name so saved tokens survive updates.
    private static let account = "notion-token-v2"

    private static var query: [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecUseAuthenticationContext as String: context]
    }

    // Legacy login-Keychain items also need process-level suppression to avoid password dialogs.
    private static func preventAuthenticationUI() throws {
        let status = SecKeychainSetUserInteractionAllowed(false)
        guard status == errSecSuccess else { throw StorageError(status: status) }
    }

    struct StorageError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Keychain: " + ((SecCopyErrorMessageString(status, nil) as String?) ?? "Error \(status)")
        }
    }

    private static func load() throws -> String {
        try preventAuthenticationUI()
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess else { throw StorageError(status: status) }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw StorageError(status: errSecDecode)
        }
        return token
    }

    private static func save(_ value: String) throws {
        try preventAuthenticationUI()
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { try delete(); return }
        let attributes = [kSecValueData as String: Data(token.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StorageError(status: status) }
        // A successful write is not enough: verify that this app can read the saved token.
        guard try load() == token else { throw StorageError(status: errSecDecode) }
    }

    private static func delete() throws {
        try preventAuthenticationUI()
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StorageError(status: status)
        }
    }

}
