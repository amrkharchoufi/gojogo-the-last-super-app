import CloudKit
import Foundation

// MARK: - CloudKit transport for the encrypted backup (E2EE Phase F)
//
// The transport handles one opaque blob and never sees anything else. The
// snapshot is sealed under the backup key before it gets here (`WorldBackup`),
// so CloudKit is exactly as untrusted as our own S3 — which is the property
// that made this an acceptable place to put a user's entire history.
//
// One record per account in the **private** database, overwritten each time.
// Not a history of snapshots: versions would multiply storage by however many
// times somebody opened the app, and the only snapshot anybody ever wants is
// the newest one.
//
// Every failure here is survivable and none of them block the user. A backup
// that didn't upload today uploads tomorrow; the local stores are still the
// live copy. So this logs and moves on rather than surfacing errors into a
// messaging UI that can do nothing useful about them.

enum WorldBackupSync {

    private static let containerId = "iCloud.com.gojo.gojogo"
    private static let recordType = "EncryptedBackup"
    private static let payloadKey = "payload"
    private static let updatedKey = "updatedAt"

    private static var container: CKContainer { CKContainer(identifier: containerId) }

    private static func recordID(for profileId: UUID) -> CKRecord.ID {
        // Deterministic: the same account always addresses the same record, so
        // an overwrite replaces rather than accumulates.
        CKRecord.ID(recordName: "backup-\(profileId.uuidString.lowercased())")
    }

    /// Whether iCloud is usable right now. A signed-out device is the ordinary
    /// case, not an error — it is precisely the situation the manual recovery
    /// code exists for, and it must never read as a failure.
    static func isAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    // MARK: Export

    /// Seals the current local state and overwrites this account's record.
    ///
    /// The payload rides as a `CKAsset` — a file reference — because CloudKit
    /// caps an inline field at 1 MB and a real history passes that quickly. An
    /// asset has no such limit and streams instead of loading whole.
    static func export(for profileId: UUID) async {
        guard await isAvailable() else { return }
        do {
            let snapshot = await MainActor.run { WorldBackup.snapshot(for: profileId) }
            let sealed = try WorldBackup.seal(snapshot, for: profileId)
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("gg-backup-\(UUID().uuidString).bin")
            try sealed.write(to: scratch, options: .atomic)
            defer { try? FileManager.default.removeItem(at: scratch) }

            let db = container.privateCloudDatabase
            let id = recordID(for: profileId)
            // Fetch-then-modify rather than a blind save: CloudKit rejects a
            // save that would clobber a record it has a newer version of, and
            // reusing the fetched record is what makes the overwrite legal.
            let record = (try? await db.record(for: id))
                ?? CKRecord(recordType: recordType, recordID: id)
            record[payloadKey] = CKAsset(fileURL: scratch)
            record[updatedKey] = Date() as NSDate
            _ = try await db.modifyRecords(saving: [record], deleting: [],
                                           savePolicy: .allKeys)
            #if DEBUG
            print("E2EE backup uploaded — \(sealed.count) bytes sealed")
            #endif
        } catch {
            #if DEBUG
            print("E2EE backup upload skipped: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: Restore

    /// Pulls and applies this account's snapshot, and reports whether anything
    /// was restored. Nil-safe in every direction: no iCloud, no record, or a
    /// record this device cannot open all mean "carry on as a new install".
    @discardableResult
    static func restore(for profileId: UUID) async -> Bool {
        guard await isAvailable() else { return false }
        do {
            let record = try await container.privateCloudDatabase
                .record(for: recordID(for: profileId))
            guard let asset = record[payloadKey] as? CKAsset,
                  let url = asset.fileURL,
                  let sealed = try? Data(contentsOf: url) else { return false }
            let snapshot = try WorldBackup.open(sealed, for: profileId)
            await MainActor.run { WorldBackup.restore(snapshot) }
            #if DEBUG
            print("E2EE backup restored — \(snapshot.archives.count) threads")
            #endif
            return true
        } catch {
            #if DEBUG
            print("E2EE backup restore skipped: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    // MARK: Lifecycle

    /// Debounced export. Called from the same mutation sites that touch the
    /// archive, so the backup tracks the history rather than a schedule — but
    /// coalesced hard, because a socket burst must not become a burst of
    /// uploads.
    @MainActor
    private static var pendingExport: Task<Void, Never>?

    @MainActor
    static func scheduleExport(for profileId: UUID) {
        pendingExport?.cancel()
        pendingExport = Task {
            try? await Task.sleep(nanoseconds: 30 * NSEC_PER_SEC)
            guard !Task.isCancelled else { return }
            await export(for: profileId)
        }
    }

    /// First run after an install: bring back the identity, then the history.
    ///
    /// Order is not incidental. The identity has to land **before** anything
    /// asks the signal store for one, because `ensureIdentity` mints lazily —
    /// one message sent first would generate a throwaway identity and hand
    /// every contact a changed safety number, which is exactly the alarm Phase
    /// E raises for a real substitution.
    static func restoreIfNeeded(for profileId: UUID) async {
        guard await isAvailable() else { return }
        do {
            if try WorldBackup.restoreIdentity(for: profileId) {
                #if DEBUG
                print("E2EE identity restored from iCloud Keychain")
                #endif
            }
        } catch {
            #if DEBUG
            print("E2EE identity restore skipped: \(error.localizedDescription)")
            #endif
        }
        await restore(for: profileId)
    }
}
