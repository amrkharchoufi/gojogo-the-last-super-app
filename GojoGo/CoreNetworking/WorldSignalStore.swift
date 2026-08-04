import Foundation
import LibSignalClient

// MARK: - libsignal protocol stores (E2EE Phase B — see E2EE-PLAN.md)
//
// Persistent, file-backed implementations of the five stores the Double
// Ratchet reads and writes through. Where things live, and why:
//
//  - The identity private key and registration id live in the **Keychain**
//    (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, like the auth
//    tokens). `KeychainStore.clearAll()` runs on sign-out, so the identity is
//    account-bound for free.
//  - Sessions, prekeys and peer identities live as flat files under a
//    `signal/` directory with `completeUntilFirstUserAuthentication`
//    protection. Files, not a database: every record is an opaque blob with
//    its own id, read whole and written whole — libsignal's records carry
//    their own structure.
//  - The base directory prefers the App Group container when the entitlement
//    exists and falls back to Application Support until then (day-one rule:
//    the future Notification Service Extension must be able to share this
//    state without migrating live ratchets; the one-time file move below
//    happens while there is still only one process, which is what makes it
//    safe).
//
// Ratchet session state is deliberately **never backed up** (see the plan's
// backup decisions): a restored stale ratchet fails silently. The directory
// is marked excluded-from-backup wholesale; the *identity* rides in the
// keychain/explicit backup path instead.

final class WorldSignalStore {
    static let shared = WorldSignalStore()

    /// The App Group both the app and the future notification extension will
    /// declare. Until the entitlement lands, `containerURL` is nil and the
    /// store lives in Application Support.
    static let appGroup = "group.com.gojo.gojogo"

    let root: URL
    private let lock = NSRecursiveLock()
    /// Identity kept in memory instead of the Keychain. Only the loopback
    /// self-check uses this — two isolated stores in one process cannot share
    /// one keychain account, and a diagnostic must never touch the real one.
    private var ephemeralIdentity: (IdentityKeyPair, UInt32)?
    private let usesKeychain: Bool

    /// `root: nil` is the real store — App Group container when the entitlement
    /// exists, Application Support until then.
    init(root: URL? = nil, usesKeychain: Bool = true) {
        let fm = FileManager.default
        self.usesKeychain = usesKeychain
        if let root {
            self.root = root
        } else {
            let base = fm.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup)
                ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.root = base.appendingPathComponent("signal", isDirectory: true)
        }
        let root = self.root
        for sub in ["sessions", "prekeys", "signed-prekeys", "kyber-prekeys", "identities"] {
            try? fm.createDirectory(
                at: root.appendingPathComponent(sub, isDirectory: true),
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        // Ratchets must not ride an iCloud/iTunes backup onto another install —
        // a stale session decrypts nothing and says nothing while failing.
        var noBackup = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? noBackup.setResourceValues(values)
    }

    // MARK: Identity bootstrap

    /// The device identity, created once and kept until sign-out. Generation
    /// happens lazily on first access — there is no separate "enroll" moment
    /// to forget to call.
    func ensureIdentity() throws -> (identity: IdentityKeyPair, registrationId: UInt32) {
        lock.lock(); defer { lock.unlock() }
        guard usesKeychain else {
            if let existing = ephemeralIdentity { return existing }
            let made = (IdentityKeyPair.generate(), UInt32.random(in: 1...0x3FFF))
            ephemeralIdentity = made
            return made
        }
        if let stored = KeychainStore.get(.signalIdentity),
           let bytes = Data(base64Encoded: stored),
           let regRaw = KeychainStore.get(.signalRegistrationId),
           let reg = UInt32(regRaw) {
            return (try IdentityKeyPair(bytes: bytes), reg)
        }
        let identity = IdentityKeyPair.generate()
        // 14 bits, nonzero — the range the protocol reserves for registration ids.
        let registrationId = UInt32.random(in: 1...0x3FFF)
        KeychainStore.set(identity.serialize().base64EncodedString(), for: .signalIdentity)
        KeychainStore.set(String(registrationId), for: .signalRegistrationId)
        return (identity, registrationId)
    }

    // MARK: File plumbing

    private func url(_ sub: String, _ name: String) -> URL {
        root.appendingPathComponent(sub, isDirectory: true)
            .appendingPathComponent(name)
    }

    private func write(_ data: Data, _ sub: String, _ name: String) throws {
        try data.write(to: url(sub, name),
                       options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func read(_ sub: String, _ name: String) -> Data? {
        try? Data(contentsOf: url(sub, name))
    }

    /// "name.deviceId", filesystem-safe: profile ids are UUIDs.
    private static func file(for address: ProtocolAddress) -> String {
        "\(address.name).\(address.deviceId)"
    }

    enum StoreError: Error {
        case missingRecord(String)
    }
}

/// The context type libsignal threads through store calls; this store keeps no
/// per-call state, so one empty marker does.
struct WorldStoreContext: StoreContext {
    init() {}
}

// MARK: - The five protocols

extension WorldSignalStore: IdentityKeyStore {
    func identityKeyPair(context: StoreContext) throws -> IdentityKeyPair {
        try ensureIdentity().identity
    }

    func localRegistrationId(context: StoreContext) throws -> UInt32 {
        try ensureIdentity().registrationId
    }

    func saveIdentity(_ identity: IdentityKey, for address: ProtocolAddress,
                      context: StoreContext) throws -> IdentityChange {
        lock.lock(); defer { lock.unlock() }
        let name = Self.file(for: address)
        let previous = read("identities", name)
        try write(identity.serialize(), "identities", name)
        if let previous, previous != identity.serialize() {
            return .replacedExisting
        }
        return .newOrUnchanged
    }

    func isTrustedIdentity(_ identity: IdentityKey, for address: ProtocolAddress,
                           direction: Direction, context: StoreContext) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        // Trust on first use. A *changed* key is not trusted silently — the
        // caller surfaces it, which is what the safety-number phase is for.
        guard let stored = read("identities", Self.file(for: address)) else { return true }
        return stored == identity.serialize()
    }

    func identity(for address: ProtocolAddress, context: StoreContext) throws -> IdentityKey? {
        lock.lock(); defer { lock.unlock() }
        guard let stored = read("identities", Self.file(for: address)) else { return nil }
        return try IdentityKey(bytes: stored)
    }
}

extension WorldSignalStore: PreKeyStore {
    func loadPreKey(id: UInt32, context: StoreContext) throws -> PreKeyRecord {
        lock.lock(); defer { lock.unlock() }
        guard let data = read("prekeys", String(id)) else {
            throw StoreError.missingRecord("prekey \(id)")
        }
        return try PreKeyRecord(bytes: data)
    }

    func storePreKey(_ record: PreKeyRecord, id: UInt32, context: StoreContext) throws {
        lock.lock(); defer { lock.unlock() }
        try write(record.serialize(), "prekeys", String(id))
    }

    func removePreKey(id: UInt32, context: StoreContext) throws {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url("prekeys", String(id)))
    }
}

extension WorldSignalStore: SignedPreKeyStore {
    func loadSignedPreKey(id: UInt32, context: StoreContext) throws -> SignedPreKeyRecord {
        lock.lock(); defer { lock.unlock() }
        guard let data = read("signed-prekeys", String(id)) else {
            throw StoreError.missingRecord("signed prekey \(id)")
        }
        return try SignedPreKeyRecord(bytes: data)
    }

    func storeSignedPreKey(_ record: SignedPreKeyRecord, id: UInt32, context: StoreContext) throws {
        lock.lock(); defer { lock.unlock() }
        try write(record.serialize(), "signed-prekeys", String(id))
    }
}

extension WorldSignalStore: KyberPreKeyStore {
    func loadKyberPreKey(id: UInt32, context: StoreContext) throws -> KyberPreKeyRecord {
        lock.lock(); defer { lock.unlock() }
        guard let data = read("kyber-prekeys", String(id)) else {
            throw StoreError.missingRecord("kyber prekey \(id)")
        }
        return try KyberPreKeyRecord(bytes: data)
    }

    func storeKyberPreKey(_ record: KyberPreKeyRecord, id: UInt32, context: StoreContext) throws {
        lock.lock(); defer { lock.unlock() }
        try write(record.serialize(), "kyber-prekeys", String(id))
    }

    func markKyberPreKeyUsed(id: UInt32, signedPreKeyId: UInt32, baseKey: PublicKey, context: StoreContext) throws {
        // Last-resort Kyber prekeys are reusable by design; nothing to delete.
        // When rotation lands, used ids recorded here inform the top-up job.
    }
}

// Fully qualified: the app has its own `SessionStore` (auth persistence), and
// the unqualified name resolves to that one.
extension WorldSignalStore: LibSignalClient.SessionStore {
    func loadSession(for address: ProtocolAddress, context: StoreContext) throws -> SessionRecord? {
        lock.lock(); defer { lock.unlock() }
        guard let data = read("sessions", Self.file(for: address)) else { return nil }
        return try SessionRecord(bytes: data)
    }

    func loadExistingSessions(for addresses: [ProtocolAddress], context: StoreContext) throws -> [SessionRecord] {
        try addresses.compactMap { try loadSession(for: $0, context: context) }
    }

    func storeSession(_ record: SessionRecord, for address: ProtocolAddress, context: StoreContext) throws {
        lock.lock(); defer { lock.unlock() }
        try write(record.serialize(), "sessions", Self.file(for: address))
    }
}
