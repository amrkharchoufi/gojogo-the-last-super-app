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

final class WorldEnvelopeVault {
    static let shared = WorldEnvelopeVault()

    private let directory: URL
    private let io = DispatchQueue(label: "app.gojogo.envelope-vault", qos: .utility)
    private let lock = NSLock()
    /// conversationId -> (messageId -> payload). Loaded lazily per conversation
    /// and kept in memory: the read happens on the render path.
    private var cache: [UUID: [UUID: WorldEnvelopePayload]] = [:]
    private var dirty: Set<UUID> = []
    private var flushScheduled = false

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        directory = base.appendingPathComponent("world-envelopes", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    }

    // MARK: Reading

    func payload(for messageId: UUID, in conversationId: UUID) -> WorldEnvelopePayload? {
        lock.lock(); defer { lock.unlock() }
        return loaded(conversationId)[messageId]
    }

    // MARK: Writing

    func store(_ payload: WorldEnvelopePayload, for messageId: UUID, in conversationId: UUID) {
        lock.lock()
        var thread = loaded(conversationId)
        thread[messageId] = payload
        cache[conversationId] = thread
        dirty.insert(conversationId)
        let schedule = !flushScheduled
        flushScheduled = true
        lock.unlock()
        guard schedule else { return }
        io.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.flush() }
    }

    /// A deleted thread's payloads go with its history.
    func remove(_ conversationId: UUID) {
        lock.lock()
        cache[conversationId] = nil
        dirty.remove(conversationId)
        lock.unlock()
        let url = fileURL(conversationId)
        io.async { try? FileManager.default.removeItem(at: url) }
    }

    /// Sign-out: these payloads are the account's plaintext, exactly like the
    /// archive, and must not outlive the account on a shared device.
    func wipe() {
        lock.lock()
        cache = [:]
        dirty = []
        lock.unlock()
        let dir = directory
        io.async {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
    }

    // MARK: Plumbing

    /// Caller holds `lock`.
    private func loaded(_ conversationId: UUID) -> [UUID: WorldEnvelopePayload] {
        if let cached = cache[conversationId] { return cached }
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
        return thread
    }

    private func flush() {
        lock.lock()
        let batch = dirty
        let snapshot = cache
        dirty = []
        flushScheduled = false
        lock.unlock()
        for id in batch {
            guard let thread = snapshot[id] else { continue }
            // JSON object keys must be strings; UUID keys would encode as an
            // array of alternating keys and values and read back as neither.
            let keyed = Dictionary(uniqueKeysWithValues:
                thread.map { ($0.key.uuidString.lowercased(), $0.value) })
            guard let data = try? JSONEncoder().encode(keyed) else { continue }
            try? data.write(to: fileURL(id),
                            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private func fileURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString.lowercased()).json")
    }
}
