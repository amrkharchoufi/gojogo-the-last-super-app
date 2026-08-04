import Foundation
import Security

/// Minimal keychain wrapper for the Cognito token set.
enum KeychainStore {
    private static let service = "app.gojogo.auth"

    enum Key: String, CaseIterable {
        case idToken, accessToken, refreshToken, tokenExpiry, accountEmail
        // E2EE (Phase B): the device's libsignal identity. In `allCases` on
        // purpose — `clearAll()` runs on sign-out, and the identity must not
        // outlive the account on a shared device.
        case signalIdentity, signalRegistrationId
    }

    static func set(_ value: String?, for key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = query
        add[kSecValueData as String] = data
        // ThisDeviceOnly: the token set — including the long-lived refresh token —
        // must not ride an encrypted iCloud/iTunes backup onto another device.
        // AfterFirstUnlock still lets a background refresh run while the phone is
        // locked in a pocket.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clearAll() {
        for key in Key.allCases {
            set(nil, for: key)
        }
    }
}

// MARK: - iCloud Keychain (E2EE Phase F — see E2EE-PLAN.md)
//
// A second, deliberately different store. Everything above is
// `ThisDeviceOnly` precisely so it cannot ride a backup off this phone; the
// items here are the opposite by design — they exist to survive the phone.
//
// Two things live here and nothing else: the **backup key** that the encrypted
// history is sealed under, and the **wrapped identity keypair**. The identity
// is what makes a reinstall invisible: restore it and contacts keep the same
// safety number, so nobody gets a "their number changed" warning for what was
// just a new handset. Ratchet sessions are never here — a restored stale
// session fails silently, which is the one failure mode the plan refuses.
//
// The trust boundary this opens is accepted knowingly and written down in the
// plan: iCloud Keychain is passcode-gated, HSM-backed and unreadable by Apple
// per their design, but it *is* Apple's escrow, and Signal-style purists keep
// keys device-only to avoid exactly this. The guarantee being bought is that a
// user who drops their phone in a river does not lose every conversation.
//
// Items are scoped by GojoGo profile id: one Apple ID can sign into two
// accounts, and restoring the wrong account's identity would be worse than
// restoring nothing.
enum ICloudKeychainStore {
    private static let service = "app.gojogo.icloud"

    static func set(_ value: String?, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
        ]
        SecItemDelete(query as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = query
        add[kSecValueData as String] = data
        // Not ThisDeviceOnly — that attribute is what *blocks* syncing, and
        // syncing is the entire point of this store.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deliberately *not* called on sign-out. Signing out is not losing your
    /// phone: if the same account signs back in, its history should still be
    /// recoverable. This is for an explicit "turn off backup" only.
    static func remove(account: String) { set(nil, account: account) }
}
