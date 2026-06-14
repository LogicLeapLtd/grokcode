import Foundation
import Security

/// Minimal Keychain wrapper for the small handful of secrets the license gate
/// needs to keep tamper-resistant: the trial-start date, the activated license
/// key, and the Lemon Squeezy instance id returned on activation.
///
/// The app has no Keychain dependency today (per the monetisation strategy doc,
/// this layer is net-new), so this is intentionally tiny — a string get/set/delete
/// keyed by a service + account. Items are stored as app-private generic passwords
/// with `kSecAttrAccessibleAfterFirstUnlock` so a launch-time validation can read
/// them without a user-present prompt.
///
/// The store degrades gracefully: if the Keychain is unavailable for any reason
/// (e.g. a future sandbox/keychain-group misconfiguration), `LicenseManager`
/// falls back to UserDefaults so the gate never hard-crashes a paying customer.
enum KeychainStore {
    /// Shared service identifier so all GrokCode license items live under one roof.
    static let service = "co.grokcode.license"

    /// Store (or overwrite) a string value for `account`. Returns true on success.
    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete any existing item first so we don't hit errSecDuplicateItem.
        delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// Read the string value for `account`, or nil if absent / unreadable.
    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    /// Remove the item for `account` (no-op if it doesn't exist).
    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
