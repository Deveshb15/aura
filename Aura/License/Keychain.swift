import Foundation
import Security

/// Minimal generic-password Keychain wrapper for license state. Net-new — the app
/// had no Keychain usage before licensing. Stores a handful of small strings (the
/// license key, its activation-instance id, the last-validated timestamp, and a
/// cached status) under a single service namespace.
///
/// Why Keychain over UserDefaults: a license key sitting in a `.plist` is
/// trivially copyable and editable, which defeats even casual anti-piracy.
/// Keychain items are encrypted at rest and scoped to the signed bundle. They
/// also survive an app reinstall, so reinstalling Carpet never forces the user to
/// re-activate. (Trade-off: an uninstall doesn't free the activation slot — that's
/// what the in-app Deactivate button is for.)
enum Keychain {
    /// One service namespace for every license item; the account disambiguates.
    static let service = "app.captureaura.license"

    /// Upserts a UTF-8 string value for `account`. Failures are swallowed —
    /// licensing degrades to "ask again" rather than crashing the app.
    static func set(_ value: String, for account: String) {
        let data = Data(value.utf8)
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = match
            insert.merge(attributes) { _, new in new }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    /// Reads the string value for `account`, or nil if absent.
    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    /// Removes the value for `account` (no-op if missing).
    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Removes every license item (used by Deactivate / reset).
    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
