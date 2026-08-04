import Foundation
import Security

/// Minimal keychain wrapper for the Cognito token set.
///
/// **Phase G moved these items into a shared access group.** The notification
/// extension needs two things out of here — the device's libsignal identity, to
/// decrypt, and the ID token, to fetch a message too large to ride in the push —
/// and a keychain item is reachable only from the access group it was written
/// to. The app's default group is its own `application-identifier`, which no
/// other bundle id can ever be granted, so a third explicitly named group is the
/// only shape that both processes can hold.
///
/// Two safeguards, because getting this wrong signs everyone out and — far
/// worse — loses the identity key, which would hand every contact a changed
/// safety number:
///
///  - Writes fall back to the unqualified (default-group) form if the shared
///    group turns out to be unusable, e.g. a build signed with a profile that
///    doesn't carry the entitlement. A probe decides that once, at first use.
///  - Reads are unqualified, which searches every group this process holds, so
///    an install that predates the migration keeps working before it runs.
enum KeychainStore {
    private static let service = "app.gojogo.auth"

    enum Key: String, CaseIterable {
        case idToken, accessToken, refreshToken, tokenExpiry, accountEmail
        // E2EE (Phase B): the device's libsignal identity. In `allCases` on
        // purpose — `clearAll()` runs on sign-out, and the identity must not
        // outlive the account on a shared device.
        case signalIdentity, signalRegistrationId
    }

    /// Whether this build can actually write to the shared access group. Probed
    /// once with a throwaway item rather than assumed: an unentitled build that
    /// assumed yes would fail every write silently, and a silent write failure
    /// on the identity key is the one outcome this file exists to prevent.
    private static let sharedGroupUsable: Bool = {
        var probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "access-group-probe",
            kSecAttrAccessGroup as String: WorldAppGroup.keychainAccessGroup,
        ]
        SecItemDelete(probe as CFDictionary)
        probe[kSecValueData as String] = Data("probe".utf8)
        probe[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(probe as CFDictionary, nil) == errSecSuccess else { return false }
        probe[kSecValueData as String] = nil
        probe[kSecAttrAccessible as String] = nil
        SecItemDelete(probe as CFDictionary)
        return true
    }()

    private static func query(_ key: Key, group: String?) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        if let group { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    static func set(_ value: String?, for key: Key) {
        // Deleted from every group this process can see, not just the one being
        // written: a stale copy in the legacy group would keep being found by an
        // unqualified read and would quietly outlive the value that replaced it.
        SecItemDelete(query(key, group: nil) as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = query(key, group: sharedGroupUsable ? WorldAppGroup.keychainAccessGroup : nil)
        add[kSecValueData as String] = data
        // ThisDeviceOnly: the token set — including the long-lived refresh token —
        // must not ride an encrypted iCloud/iTunes backup onto another device.
        // AfterFirstUnlock still lets a background refresh run while the phone is
        // locked in a pocket — and is what lets the notification extension read
        // this at 3am, without the user having unlocked since the last reboot.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: Key) -> String? {
        // Unqualified: searches every access group this process holds, which is
        // the shared one plus its own. One lookup covers both the migrated and
        // the not-yet-migrated case.
        read(query(key, group: nil))
    }

    private static func read(_ base: [String: Any]) -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
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

    /// One-time move of every item into the shared access group (Phase G).
    ///
    /// Runs from the app and only from the app, at launch, before anything
    /// reads. The extension must never do this: it cannot see the legacy group,
    /// so from over there "no item" and "not migrated yet" look identical — and
    /// acting on that confusion is how a device mints a second identity and
    /// changes its safety number with everyone it knows.
    ///
    /// Idempotent, and a no-op on a fresh install (nothing to move) or an
    /// unentitled build (nowhere to move it to).
    static func migrateToSharedAccessGroup() {
        guard sharedGroupUsable else { return }
        for key in Key.allCases {
            let shared = query(key, group: WorldAppGroup.keychainAccessGroup)
            if read(shared) != nil { continue }
            let legacy = query(key, group: WorldAppGroup.legacyKeychainAccessGroup)
            guard let value = read(legacy), let data = value.data(using: .utf8) else { continue }
            var add = shared
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            // The legacy copy goes only once the new one is really there. A
            // delete that ran first, against a write that failed, would take the
            // identity with it.
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { continue }
            SecItemDelete(legacy as CFDictionary)
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
