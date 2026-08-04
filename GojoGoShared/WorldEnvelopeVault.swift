import Foundation

// MARK: - Opened-payload vault (E2EE Phase C — see E2EE-PLAN.md)
//
// The ledger that makes "decrypts exactly once" survivable.
//
// A Double Ratchet message key is deleted the moment it is used, so opening the
// same ciphertext twice is not a retry — the second attempt throws and the
// message is unreadable by anyone, forever. The app's fetch path does exactly
// that by design: `reloadLiveConversation` re-pulls the newest page on every
// open, and the socket delivers messages the next fetch will hand back again.
// So the opened payload is written here the first time and served from here
// afterwards; libsignal is asked to decrypt only bytes nobody has opened yet.
//
// It also carries the other half of the asymmetry: **a sender cannot read its
// own ciphertext**, which is sealed to the peer's ratchet. Outgoing payloads
// are recorded at seal time under the *client* id (the only id that exists
// before the server answers), then re-keyed onto the server id the first time
// an echo arrives. Fetched pages carry `clientId` too, so a send interrupted
// between seal and response still resolves after a relaunch.
//
// Why not reuse `WorldMessageArchive`: the archive stores rendered
// `WorldMessage`s per conversation for display. This stores raw payloads keyed
// by message id — including client ids the archive never sees — and its job is
// to answer one question at the wire boundary, before a `WorldMessage` exists.
//
// Failures are deliberately **not** recorded. Some are transient (the store is
// unreadable before first unlock; the profile id isn't loaded yet), and caching
// those would turn a message that will open fine in a second into a permanent
// "couldn't be decrypted".
//
// **Phase G made this shared and synchronous.** The notification extension
// opens messages too, in its own process, and the two stay consistent only if:
//
//  - the files live in the **App Group container** (with the same one-time move
//    the signal store does, for installs that predate the entitlement);
//  - a write reaches disk **before** the ratchet lock is released — a debounced
//    flush would let the other process ask libsignal to open a ciphertext this
//    one had already spent; and
//  - a read notices when the *other* process has written. Hence the mtime
//    check: an in-memory cache that never re-reads is worse than no cache here.

final class WorldEnvelopeVault {
    static let shared = WorldEnvelopeVault()

    private let directory: URL
    private let lock = NSLock()
    /// conversationId -> (messageId -> payload). Loaded lazily per conversation
    /// and kept in memory: the read happens on the render path.
    private var cache: [UUID: [UUID: WorldEnvelopePayload]] = [:]
    /// The modification date each cached conversation was loaded at. A file
    /// newer than this was written by the other process.
    private var loadedAt: [UUID: Date] = [:]

    private init() {
        let fm = FileManager.default
        let legacy = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("world-envelopes", isDirectory: true)
        if let container = WorldAppGroup.containerURL {
            let moved = container.appendingPathComponent("world-envelopes", isDirectory: true)
            // The same one-time move `WorldSignalStore` does, load-bearing for
            // the same reason: the vault *relocates* on the first launch after
            // the App Group entitlement lands, and a vault that reads as empty
            // is a vault that asks libsignal to reopen every spent ciphertext in
            // the newest page. Safe in `init` — one process, nothing mid-flight.
            if !fm.fileExists(atPath: moved.path), fm.fileExists(atPath: legacy.path) {
                try? fm.moveItem(at: legacy, to: moved)
            }
            directory = moved
        } else {
            directory = legacy
        }
        try? fm.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    }

    // MARK: Reading

    func payload(for messageId: UUID, in conversationId: UUID) -> WorldEnvelopePayload? {
        lock.lock(); defer { lock.unlock() }
        return loaded(conversationId)[messageId]
    }

    // MARK: Writing

    /// Records an opened payload and returns once it is on disk.
    ///
    /// Synchronous on purpose (Phase G): the caller is holding the ratchet lock,
    /// and the point of that lock is that the *other* process finds this payload
    /// rather than spending the message key a second time. A write still sitting
    /// in memory when the lock is released would defeat it.
    func store(_ payload: WorldEnvelopePayload, for messageId: UUID, in conversationId: UUID) {
        lock.lock(); defer { lock.unlock() }
        var thread = loaded(conversationId)
        thread[messageId] = payload
        cache[conversationId] = thread
        write(thread, to: conversationId)
    }

    /// A deleted thread's payloads go with its history.
    func remove(_ conversationId: UUID) {
        lock.lock(); defer { lock.unlock() }
        cache[conversationId] = nil
        loadedAt[conversationId] = nil
        try? FileManager.default.removeItem(at: fileURL(conversationId))
    }

    /// Sign-out: these payloads are the account's plaintext, exactly like the
    /// archive, and must not outlive the account on a shared device.
    func wipe() {
        lock.lock(); defer { lock.unlock() }
        cache = [:]
        loadedAt = [:]
        let fm = FileManager.default
        try? fm.removeItem(at: directory)
        try? fm.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    }

    // MARK: Backup (Phase F)

    func exportFiles() -> [String: Data] {
        var out: [String: Data] = [:]
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(".json") {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { continue }
            out[String(name.dropLast(5))] = data
        }
        return out
    }

    func importFiles(_ files: [String: Data]) {
        lock.lock(); cache = [:]; loadedAt = [:]; lock.unlock()
        for (id, data) in files {
            try? data.write(to: directory.appendingPathComponent("\(id).json"),
                            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    // MARK: Plumbing

    /// Caller holds `lock`. Re-reads whenever the file on disk is newer than the
    /// copy in memory — which is how a payload the *extension* opened reaches
    /// the app without a relaunch.
    private func loaded(_ conversationId: UUID) -> [UUID: WorldEnvelopePayload] {
        let stamp = modifiedAt(conversationId)
        if let cached = cache[conversationId], loadedAt[conversationId] == stamp {
            return cached
        }
        let thread: [UUID: WorldEnvelopePayload]
        if let data = try? Data(contentsOf: fileURL(conversationId)),
           let decoded = try? JSONDecoder().decode([String: WorldEnvelopePayload].self, from: data) {
            thread = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            })
        } else {
            thread = [:]
        }
        cache[conversationId] = thread
        loadedAt[conversationId] = stamp
        return thread
    }

    /// Caller holds `lock`.
    private func write(_ thread: [UUID: WorldEnvelopePayload], to conversationId: UUID) {
        // JSON object keys must be strings; UUID keys would encode as an array
        // of alternating keys and values and read back as neither.
        let keyed = Dictionary(uniqueKeysWithValues:
            thread.map { ($0.key.uuidString.lowercased(), $0.value) })
        guard let data = try? JSONEncoder().encode(keyed) else { return }
        try? data.write(to: fileURL(conversationId),
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        loadedAt[conversationId] = modifiedAt(conversationId)
    }

    private func modifiedAt(_ conversationId: UUID) -> Date? {
        let attributes = try? FileManager.default
            .attributesOfItem(atPath: fileURL(conversationId).path)
        return attributes?[.modificationDate] as? Date
    }

    private func fileURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString.lowercased()).json")
    }
}
