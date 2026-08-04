import CryptoKit
import Foundation
import LibSignalClient

// MARK: - Encrypted backup & restore (E2EE Phase F — see E2EE-PLAN.md)
//
// Forward secrecy has a cost, and this phase is the bill. A ciphertext opens
// once, so the server's copy is a delivery and not an archive — meaning the
// only copy of a conversation is the one on the device. Lose the device and it
// is gone, by construction. Phases C–E made that true; this makes it survivable.
//
// **What is backed up, and what must never be.**
//   - History (`WorldMessageArchive`), opened payloads (`WorldEnvelopeVault`),
//     media keys and verification records: yes. These are the account's
//     plaintext and they are irreplaceable.
//   - The **identity keypair**: yes, and it is the important one. Restore it
//     and a reinstall is invisible — contacts keep the same safety number and
//     nobody gets a "their number changed" warning for a new handset. Without
//     it, every restore would look exactly like the attack Phase E exists to
//     detect, which would teach people that the warning means nothing.
//   - **Ratchet sessions: never.** A restored session is stale on arrival —
//     the peer has moved on, the chain keys no longer line up, and it fails
//     *silently*. Sessions re-establish from the prekey directory under the
//     unchanged identity, which costs one round trip and always works.
//
// The snapshot is sealed with a random backup key that lives in iCloud
// Keychain, so the transport never sees plaintext. That is what lets the
// eventual CloudKit record be exactly as untrusted as our own S3.

struct WorldBackupSnapshot: Codable {
    /// Which GojoGo account this belongs to. One Apple ID can sign into two,
    /// and restoring the wrong account's history is worse than restoring none.
    var profileId: String
    var createdAt: Date
    /// Schema version, so a newer snapshot can be *refused* rather than
    /// half-read. Restoring a payload we only partly understand would silently
    /// drop messages.
    var version: Int = 1

    /// `conversationId -> the archive file's bytes`, verbatim.
    var archives: [String: Data] = [:]
    /// `conversationId -> the vault file's bytes`, verbatim.
    var vaults: [String: Data] = [:]
    var mediaKeys: [String: String] = [:]
    var verifiedKeys: [String: String] = [:]
}

enum WorldBackup {

    enum BackupError: LocalizedError {
        case noBackupKey
        case wrongAccount
        case unreadable
        case tooNew(Int)

        var errorDescription: String? {
            switch self {
            case .noBackupKey: return "No backup key was found in your iCloud Keychain."
            case .wrongAccount: return "That backup belongs to a different account."
            case .unreadable: return "The backup couldn't be read."
            case .tooNew: return "This backup needs a newer version of GojoGo."
            }
        }
    }

    static let version = 1

    // MARK: Key material

    private static func backupKeyAccount(_ profileId: UUID) -> String {
        "backup-key.\(profileId.uuidString.lowercased())"
    }

    private static func identityAccount(_ profileId: UUID) -> String {
        "identity.\(profileId.uuidString.lowercased())"
    }

    /// The key this account's snapshots are sealed under, minted once and then
    /// stable forever — a rotating key would orphan every existing snapshot.
    static func backupKey(for profileId: UUID, creatingIfNeeded: Bool = true) -> SymmetricKey? {
        let account = backupKeyAccount(profileId)
        if let stored = ICloudKeychainStore.get(account: account),
           let raw = Data(base64Encoded: stored), raw.count == 32 {
            return SymmetricKey(data: raw)
        }
        guard creatingIfNeeded else { return nil }
        let key = SymmetricKey(size: .bits256)
        ICloudKeychainStore.set(key.withUnsafeBytes { Data($0) }.base64EncodedString(),
                                account: account)
        return key
    }

    /// Puts this device's identity keypair where a reinstall can find it.
    ///
    /// Wrapped under the backup key rather than stored bare: iCloud Keychain is
    /// already strong, but the identity is the one secret whose loss is
    /// permanent and whose theft is total, and it costs nothing to not rely on
    /// a single control.
    static func backUpIdentity(for profileId: UUID) throws {
        guard let key = backupKey(for: profileId) else { throw BackupError.noBackupKey }
        let identity = try WorldSignalStore.shared.ensureIdentity()
        var blob = Data()
        blob.append(contentsOf: withUnsafeBytes(of: identity.registrationId.bigEndian) { Data($0) })
        blob.append(identity.identity.serialize())
        let sealed = try AES.GCM.seal(blob, using: key)
        guard let combined = sealed.combined else { throw BackupError.unreadable }
        ICloudKeychainStore.set(combined.base64EncodedString(),
                                account: identityAccount(profileId))
    }

    /// Restores the identity, or nil when this Apple ID has never backed one up
    /// for this account — a genuinely new user, who simply generates one.
    @discardableResult
    static func restoreIdentity(for profileId: UUID) throws -> Bool {
        guard let stored = ICloudKeychainStore.get(account: identityAccount(profileId)),
              let combined = Data(base64Encoded: stored) else { return false }
        guard let key = backupKey(for: profileId, creatingIfNeeded: false) else {
            throw BackupError.noBackupKey
        }
        let blob: Data
        do {
            blob = try AES.GCM.open(try AES.GCM.SealedBox(combined: combined), using: key)
        } catch {
            throw BackupError.unreadable
        }
        guard blob.count > 4 else { throw BackupError.unreadable }
        let registrationId = blob.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let identity = try IdentityKeyPair(bytes: blob.dropFirst(4))
        WorldSignalStore.shared.adoptRestoredIdentity(identity, registrationId: registrationId)
        return true
    }

    // MARK: Snapshot

    static func snapshot(for profileId: UUID) -> WorldBackupSnapshot {
        var snap = WorldBackupSnapshot(profileId: profileId.uuidString.lowercased(),
                                       createdAt: Date(), version: version)
        snap.archives = WorldMessageArchive.shared.exportFiles()
        snap.vaults = WorldEnvelopeVault.shared.exportFiles()
        snap.mediaKeys = WorldMediaKeyStore.shared.exportAll()
        snap.verifiedKeys = WorldVerificationStore.shared.exportAll()
        return snap
    }

    static func seal(_ snapshot: WorldBackupSnapshot, for profileId: UUID) throws -> Data {
        guard let key = backupKey(for: profileId) else { throw BackupError.noBackupKey }
        let plain = try JSONEncoder().encode(snapshot)
        guard let combined = try AES.GCM.seal(plain, using: key).combined else {
            throw BackupError.unreadable
        }
        return combined
    }

    static func open(_ sealed: Data, for profileId: UUID) throws -> WorldBackupSnapshot {
        guard let key = backupKey(for: profileId, creatingIfNeeded: false) else {
            throw BackupError.noBackupKey
        }
        let plain: Data
        do {
            plain = try AES.GCM.open(try AES.GCM.SealedBox(combined: sealed), using: key)
        } catch {
            throw BackupError.unreadable
        }
        guard let snapshot = try? JSONDecoder().decode(WorldBackupSnapshot.self, from: plain) else {
            throw BackupError.unreadable
        }
        guard snapshot.version <= version else { throw BackupError.tooNew(snapshot.version) }
        guard snapshot.profileId == profileId.uuidString.lowercased() else {
            throw BackupError.wrongAccount
        }
        return snapshot
    }

    /// Writes a snapshot back over the local stores.
    ///
    /// Sessions are pointedly absent: the identity comes back, every ratchet
    /// starts again. That is not a shortcut — a restored session decrypts
    /// nothing and says nothing while failing.
    static func restore(_ snapshot: WorldBackupSnapshot) {
        WorldMessageArchive.shared.importFiles(snapshot.archives)
        WorldEnvelopeVault.shared.importFiles(snapshot.vaults)
        WorldMediaKeyStore.shared.register(snapshot.mediaKeys)
        WorldVerificationStore.shared.importAll(snapshot.verifiedKeys)
    }
}
