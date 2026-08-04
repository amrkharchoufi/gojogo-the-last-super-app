import CryptoKit
import Foundation

// MARK: - Media encryption (E2EE Phase D — see E2EE-PLAN.md)
//
// Phase C sealed the *text*. A photo still went to the CDN in the clear, which
// made the honest version of the claim "your messages are end-to-end encrypted
// unless they contain a picture". This closes that.
//
// Each file gets its own random AES-256-GCM key, used once. The bytes are
// encrypted **before** `uploadMedia`, so the CDN — and anyone who can read an
// S3 object or a signed URL — stores ciphertext. The key travels inside the
// message's sealed envelope, which means it is protected by the ratchet and by
// nothing weaker.
//
// **Why the URL stays visible.** The server reference-counts uploads by URL
// (`media.markReferenced`), so the pointer cannot be opaque without rewriting
// how uploads are garbage-collected. That was settled in Phase A: encrypt what
// is *behind* the pointer. What leaks is that a message has an attachment and
// roughly how big it is — never what it is.
//
// GCM and not CBC because the tag makes tampering fail loudly: a CDN object
// somebody rewrote does not decode to a subtly different image, it refuses to
// open at all.

enum WorldMediaCrypto {

    enum MediaCryptoError: Error {
        case badKey
        /// The bytes did not authenticate: wrong key, or the object was
        /// modified in storage. Deliberately not distinguished — telling an
        /// attacker which of the two happened is free information.
        case undecryptable
    }

    /// Encrypts one file and returns the bytes to upload plus the key to put in
    /// the envelope. The nonce rides inside `combined`, so the key is the only
    /// thing the payload has to carry.
    static func seal(_ plaintext: Data) throws -> (ciphertext: Data, key: String) {
        let key = SymmetricKey(size: .bits256)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw MediaCryptoError.undecryptable }
        let raw = key.withUnsafeBytes { Data($0) }
        return (combined, raw.base64EncodedString())
    }

    static func open(_ ciphertext: Data, key base64Key: String) throws -> Data {
        guard let raw = Data(base64Encoded: base64Key), raw.count == 32 else {
            throw MediaCryptoError.badKey
        }
        let key = SymmetricKey(data: raw)
        do {
            return try AES.GCM.open(try AES.GCM.SealedBox(combined: ciphertext), using: key)
        } catch {
            throw MediaCryptoError.undecryptable
        }
    }
}

/// Collects the per-file keys minted while one message's attachments upload.
///
/// A key exists before its URL does — the file has to be encrypted to be
/// uploaded, and the URL only comes back from the upload — so something has to
/// hold the pair until both halves are known. That is all this is.
///
/// `active: false` makes it a pass-through, which is how avatars, story frames
/// and marketplace photos keep using the same upload helpers untouched: only a
/// 1:1 chat message whose envelope will actually be sealed gets a live one.
@MainActor
final class WorldMediaSealer {
    let active: Bool
    private(set) var keys: [String: String] = [:]

    init(active: Bool) { self.active = active }

    func upload(_ data: Data, contentType: String) async throws -> String {
        guard active else {
            return try await APIClient.shared.uploadMedia(data, contentType: contentType)
        }
        let sealed = try WorldMediaCrypto.seal(data)
        // The content type is the *plaintext's* — S3 stores bytes and the
        // backend whitelists the type, so claiming the real one keeps the
        // presign valid. Nothing renders these bytes without decrypting first.
        let url = try await APIClient.shared.uploadMedia(sealed.ciphertext, contentType: contentType)
        keys[url] = sealed.key
        return url
    }

    /// Registers what was minted so this device can read back its own uploads —
    /// the sender never receives its own envelope, so nothing else would.
    func registerLocally() {
        WorldMediaKeyStore.shared.register(keys)
    }
}

// MARK: - URL → key registry
//
// Every media surface in the app — `MediaImage`, `CachedAsyncImage`,
// `ImageCache`, the video and audio players — addresses a file by its URL and
// nothing else. Threading a decryption key down through all of them would touch
// the feed, stories, profiles and the marketplace to serve chat alone.
//
// So the key is looked up *by URL* at fetch time instead. `ImageCache` asks
// this registry; if there is no key the bytes are used as they always were,
// which is what keeps every non-chat image and every pre-Phase-D attachment
// working untouched.
//
// Persisted, and that is load-bearing: the URL survives in the message archive,
// so a key held only in memory would make every attachment unreadable after a
// relaunch — the same trap `WorldEnvelopeVault` exists to avoid for text.

final class WorldMediaKeyStore {
    static let shared = WorldMediaKeyStore()

    private let fileURL: URL
    private let io = DispatchQueue(label: "app.gojogo.media-keys", qos: .utility)
    private let lock = NSLock()
    private var keysByURL: [String: String] = [:]
    private var loaded = false
    private var flushScheduled = false

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        fileURL = base.appendingPathComponent("world-media-keys.json")
    }

    /// Nil for anything this device has no key for — every non-chat image, and
    /// every attachment sent before Phase D. Those are used verbatim.
    func key(for url: URL) -> String? {
        lock.lock(); defer { lock.unlock() }
        loadIfNeeded()
        return keysByURL[url.absoluteString]
    }

    func register(_ keys: [String: String]) {
        guard !keys.isEmpty else { return }
        lock.lock()
        loadIfNeeded()
        keysByURL.merge(keys) { _, new in new }
        let schedule = !flushScheduled
        flushScheduled = true
        lock.unlock()
        guard schedule else { return }
        io.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.flush() }
    }

    /// Sign-out. These keys open the account's photos; they must not outlive it
    /// on a shared device any more than the archive does.
    func wipe() {
        lock.lock()
        keysByURL = [:]
        loaded = true
        flushScheduled = false
        lock.unlock()
        let url = fileURL
        io.async { try? FileManager.default.removeItem(at: url) }
    }

    /// Backup (Phase F): media keys are as irreplaceable as the messages —
    /// without them every restored attachment is an unopenable CDN object.
    func exportAll() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        loadIfNeeded()
        return keysByURL
    }

    /// Caller holds `lock`.
    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        keysByURL = decoded
    }

    private func flush() {
        lock.lock()
        let snapshot = keysByURL
        flushScheduled = false
        lock.unlock()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL,
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
