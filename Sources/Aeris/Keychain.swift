import Foundation
import Security

/// Small wrapper around the login Keychain. Each value is a generic password under one service.
enum Keychain {
    private static let service = ProcessInfo.processInfo.environment["AERIS_KEYCHAIN_SERVICE"]
        ?? "com.kashmithnisakya.aeris.smartthings"

    enum Account: String {
        case legacyToken = "token"          // personal access token saved by Aeris 1.x
        case credentials = "credentials"    // JSON-encoded Credentials
        case oauthClient = "oauthClient"    // JSON-encoded OAuthClient the user entered
    }

    static func data(_ account: Account) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    @discardableResult
    static func set(_ data: Data, for account: Account) -> Bool {
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: Account) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func get<T: Decodable>(_ type: T.Type, _ account: Account) -> T? {
        data(account).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    @discardableResult
    static func put<T: Encodable>(_ value: T, _ account: Account) -> Bool {
        guard let d = try? JSONEncoder().encode(value) else { return false }
        return set(d, for: account)
    }
}
