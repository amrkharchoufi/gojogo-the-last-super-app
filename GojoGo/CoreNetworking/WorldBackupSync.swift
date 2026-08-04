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

    // MARK: Observable state
    //
    // A backup nobody can see is one nobody can trust. These are the three
    // facts a user actually needs — is it on, when did it last work, how big —
    // and they are written from the same places that do the work, so the
    // screen cannot claim a backup that did not happen.

    private static let lastBackupKey = "world.backup.lastAt"
    private static let lastSizeKey = "world.backup.lastBytes"
    private static let disabledKey = "world.backup.disabled"

    static var lastBackupAt: Date? {
        let stamp = UserDefaults.standard.double(forKey: lastBackupKey)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    static var lastBackupBytes: Int {
        UserDefaults.standard.integer(forKey: lastSizeKey)
    }

    /// How often the backup is allowed to run.
    ///
    /// A cadence rather than a bare on/off because the two ends of the trade
    /// are real: every upload re-seals and re-sends the whole history, so a
    /// chatty account on daily costs data and battery, while monthly means a
    /// lost phone can cost a month of messages. Daily is the default because
    /// losing a month is the worse surprise.
    ///
    /// Off does not delete what is already stored — "stop backing up" and
    /// "destroy my history" are different requests, and only one is reversible.
    enum Frequency: String, CaseIterable, Identifiable {
        case off, daily, weekly, monthly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: return "Off"
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            }
        }

        /// Minimum gap between uploads. Nil means never.
        var interval: TimeInterval? {
            switch self {
            case .off: return nil
            case .daily: return 24 * 3600
            case .weekly: return 7 * 24 * 3600
            case .monthly: return 30 * 24 * 3600
            }
        }
    }

    private static let frequencyKey = "world.backup.frequency"

    static var frequency: Frequency {
        get {
            guard let raw = UserDefaults.standard.string(forKey: frequencyKey) else {
                // Migration from the original boolean: an account that had
                // backup on stays on, at the default cadence.
                return UserDefaults.standard.bool(forKey: disabledKey) ? .off : .daily
            }
            return Frequency(rawValue: raw) ?? .daily
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: frequencyKey)
            UserDefaults.standard.set(newValue == .off, forKey: disabledKey)
        }
    }

    static var isEnabled: Bool { frequency != .off }

    /// Whether enough time has passed since the last successful upload.
    /// A first-ever backup is always due — otherwise a new account would wait
    /// a day before its history was protected at all.
    static var isDue: Bool {
        guard let interval = frequency.interval else { return false }
        guard let last = lastBackupAt else { return true }
        return Date().timeIntervalSince(last) >= interval
    }

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
    /// `force` is the "Back up now" button: an explicit request ignores the
    /// cadence, because a user who taps it is asking for exactly one upload.
    static func export(for profileId: UUID, force: Bool = false) async {
        guard isEnabled, force || isDue, await isAvailable() else { return }
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
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastBackupKey)
            UserDefaults.standard.set(sealed.count, forKey: lastSizeKey)
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
        // Cheap enough to check before arming: on a cadence of weekly, almost
        // every message would otherwise arm a timer that wakes only to decide
        // it has nothing to do.
        guard isEnabled, isDue else { return }
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
