import Foundation
import LibSignalClient

// MARK: - Safety numbers (E2EE Phase E — see E2EE-PLAN.md)
//
// The plan calls this a v1 requirement rather than polish, and the reason is
// worth being blunt about: **our own key directory is the weak point until this
// ships.** Every session starts from a bundle the server hands out. A server
// that handed out its own bundle instead would sit in the middle of a
// conversation both ends believe is encrypted, and nothing in Phases C or D
// would notice — the ratchet works perfectly with the wrong peer.
//
// A safety number is the only thing that closes that. It is a digest of the two
// *identity public keys*, so it can only match if both sides hold the keys they
// think they hold. Comparing it out of band — read it aloud, look at each
// other's screen — is what turns "the directory says this is them" into "they
// told me this is them".
//
// Two states, and the difference matters:
//
//   - **Unverified.** The overwhelmingly common case. A key change here is a
//     reinstall, and gets the neutral in-thread line Phase C already shows.
//   - **Verified.** The user explicitly compared numbers. A key change *now* is
//     the one event that deserves a real warning, because the user has already
//     established what the right key was.
//
// Warning on both would train people to dismiss it, which is worse than not
// warning at all — that is why the recovery in `WorldSignalSession` stays
// automatic and quiet unless the contact was verified.

enum WorldSafetyNumber {

    /// Signal's parameters. Not ours to pick: an interoperable 60-digit safety
    /// number is only comparable if both sides derive it identically, and these
    /// are the constants that definition fixes.
    private static let iterations = 5200
    private static let version = 2

    /// The 60-digit number for a conversation with `peer`, or nil before the
    /// first session exists (there is no peer identity key to digest yet).
    ///
    /// The two identifiers are sorted into the generator by *role*, not by
    /// value — local always local — and libsignal orders the halves internally,
    /// so both devices arrive at the same number without agreeing on who is
    /// "first".
    @MainActor
    static func fingerprint(with peer: UUID) -> Fingerprint? {
        guard let me = MessagingStore.shared.myProfileId ?? SocialStore.shared.myProfileId,
              let them = try? WorldSignalSession.address(for: peer),
              let theirKey = try? WorldSignalStore.shared.identity(for: them,
                                                                   context: WorldStoreContext()),
              let mine = try? WorldSignalStore.shared.ensureIdentity()
        else { return nil }
        return try? NumericFingerprintGenerator(iterations: iterations).create(
            version: version,
            localIdentifier: Data(me.uuidString.lowercased().utf8),
            localKey: mine.identity.publicKey,
            remoteIdentifier: Data(peer.uuidString.lowercased().utf8),
            remoteKey: theirKey.publicKey)
    }

    /// The number as people actually read it: twelve groups of five digits.
    /// Chunking is not decoration — comparing sixty undifferentiated digits out
    /// loud is where mistakes come from.
    @MainActor
    static func displayNumber(with peer: UUID) -> String? {
        guard let raw = fingerprint(with: peer)?.displayable.formatted else { return nil }
        return stride(from: 0, to: raw.count, by: 5).map { offset in
            let start = raw.index(raw.startIndex, offsetBy: offset)
            let end = raw.index(start, offsetBy: min(5, raw.count - offset))
            return String(raw[start..<end])
        }.joined(separator: " ")
    }
}

// MARK: - What the user actually vouched for

/// Records the peer identity key at the moment the user said "this is them",
/// and answers the only two questions that matter afterwards: is this contact
/// verified, and is the key still the one they verified.
///
/// The *key* is stored, not a boolean. A boolean would survive a key change and
/// go on claiming a contact is verified after the thing they verified was
/// replaced — which is precisely the attack this phase exists to catch.
final class WorldVerificationStore {
    static let shared = WorldVerificationStore()

    enum Status {
        case unverified
        case verified
        /// Verified once, but the peer's identity key has since changed. The
        /// strong-warning case, and the only one.
        case changedAfterVerification
    }

    private let fileURL: URL
    private let io = DispatchQueue(label: "app.gojogo.verification", qos: .utility)
    private let lock = NSLock()
    /// `peerId -> base64 identity key the user verified`.
    private var verifiedKeys: [String: String] = [:]
    private var loaded = false

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        fileURL = base.appendingPathComponent("world-verified-keys.json")
    }

    @MainActor
    func status(of peer: UUID) -> Status {
        guard let vouched = storedKey(for: peer) else { return .unverified }
        guard let current = currentKey(of: peer) else {
            // Verified, and we have since forgotten their key entirely — a
            // sign-out, or `forgetPeer` after a change. Treat as changed rather
            // than unverified: the user's earlier judgement is not evidence
            // about whoever turns up next.
            return .changedAfterVerification
        }
        return current == vouched ? .verified : .changedAfterVerification
    }

    /// Records the key this contact currently presents as the one the user
    /// vouched for. No-ops when there is no session yet — there is nothing to
    /// have compared.
    @MainActor
    @discardableResult
    func markVerified(_ peer: UUID) -> Bool {
        guard let current = currentKey(of: peer) else { return false }
        write { $0[peer.uuidString.lowercased()] = current }
        return true
    }

    @MainActor
    func clearVerification(_ peer: UUID) {
        write { $0[peer.uuidString.lowercased()] = nil }
    }

    /// Sign-out: one account's judgements say nothing about the next one's
    /// contacts, and a stale "verified" is worse than no claim at all.
    func wipe() {
        lock.lock()
        verifiedKeys = [:]
        loaded = true
        lock.unlock()
        let url = fileURL
        io.async { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: Plumbing

    @MainActor
    private func currentKey(of peer: UUID) -> String? {
        guard let them = try? WorldSignalSession.address(for: peer),
              let key = try? WorldSignalStore.shared.identity(for: them,
                                                              context: WorldStoreContext())
        else { return nil }
        return key.serialize().base64EncodedString()
    }

    /// Backup (Phase F). Restoring these matters more than it looks: the
    /// identity comes back with the backup, so a contact verified before the
    /// restore is still legitimately verified after it — dropping the record
    /// would demand the user re-verify everyone for no reason.
    func exportAll() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        loadIfNeeded()
        return verifiedKeys
    }

    func importAll(_ keys: [String: String]) {
        write { $0.merge(keys) { _, new in new } }
    }

    private func storedKey(for peer: UUID) -> String? {
        lock.lock(); defer { lock.unlock() }
        loadIfNeeded()
        return verifiedKeys[peer.uuidString.lowercased()]
    }

    private func write(_ mutate: (inout [String: String]) -> Void) {
        lock.lock()
        loadIfNeeded()
        mutate(&verifiedKeys)
        let snapshot = verifiedKeys
        lock.unlock()
        let url = fileURL
        io.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url,
                            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// Caller holds `lock`.
    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        verifiedKeys = decoded
    }
}
