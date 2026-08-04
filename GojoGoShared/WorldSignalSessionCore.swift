import Foundation
import LibSignalClient

// MARK: - Double Ratchet sessions, the part with no app in it (Phase C/G)
//
// The seam Phase A left behind: `WorldEnvelope` used to hand its payload to an
// identity transform, and now hands it here. Everything around it — the wire
// shape, the local archive, previews, push — was built and verified while the
// payload was still readable, so a blank bubble in Phase C has exactly one
// suspect: this file and its app-side companion.
//
// Three things are worth knowing before reading further.
//
// **A ciphertext decrypts exactly once, ever.** The message key is deleted on
// use, and that deletion *is* forward secrecy. So nothing may call `open` twice
// on the same bytes — the second call throws `duplicatedMessage` and the
// message is gone for good. `WorldEnvelopeVault` is what makes that safe, and
// since Phase G `WorldRatchetLock` is what makes it safe across two processes.
//
// **A sender cannot read its own ciphertext.** It is sealed to the peer's
// ratchet, not ours. Our own sent messages are readable only because the vault
// records the payload at seal time, under the client id.
//
// **Sessions are per *peer*, not per conversation.** Phase A guessed the
// opposite; the address here is a profile id plus a device id, which is why
// the day-one `deviceId` rule exists and why multi-device is schema-ready.
//
// Everything in this file takes its store and its addresses as arguments, which
// is what lets three very different callers share it: the app, the notification
// extension, and the loopback self-check that drives two isolated stores in one
// process.

enum WorldSignalSession {

    /// v1 has one device per account. The wire and the directory have carried a
    /// device id since day one so this can stop being a constant without a
    /// migration nobody can perform (the server cannot rewrite what it can't
    /// read).
    static let deviceId: UInt32 = 1

    enum SessionError: LocalizedError {
        /// No session, and the peer has published no bundle to start one from.
        /// The one condition under which a thread legitimately stays on the
        /// readable envelope — see `WorldEnvelope`'s downgrade rule.
        case peerHasNoKeys
        /// Our own profile id isn't known yet (messaging hasn't connected).
        /// Transient by construction: never cache a failure caused by it.
        case identityUnavailable
        case malformedCiphertext
        /// The peer's identity key changed after the user verified it, and
        /// they haven't looked at the new one. Phase E: only a *verified*
        /// contact blocks a send — see `sealedBody`.
        case verificationStale

        var errorDescription: String? {
            switch self {
            case .peerHasNoKeys: return "That contact hasn't set up encryption yet."
            case .identityUnavailable: return "Encryption isn't ready yet."
            case .malformedCiphertext: return "The message body was damaged."
            case .verificationStale:
                return "Their safety number changed. Verify it again before sending."
            }
        }
    }

    static func address(for profileId: UUID) throws -> ProtocolAddress {
        // Lowercased without exception: the address name is the session file's
        // name, so a case difference between the send and receive paths would
        // silently open a *second*, empty session with the same person.
        try ProtocolAddress(name: profileId.uuidString.lowercased(), deviceId: deviceId)
    }

    // MARK: Framing
    //
    // libsignal's ciphertext does not say which of the two message types it is,
    // and the two open through different functions. One leading byte carries
    // `CiphertextMessage.MessageType`; the rest is the serialized message.

    static func frame(_ message: CiphertextMessage) -> Data {
        var out = Data([message.messageType.rawValue])
        out.append(message.serialize())
        return out
    }

    static func unframe(_ data: Data) throws -> (type: CiphertextMessage.MessageType, body: Data) {
        guard let first = data.first, data.count > 1 else {
            throw SessionError.malformedCiphertext
        }
        return (CiphertextMessage.MessageType(rawValue: first), Data(data.dropFirst()))
    }

    // MARK: Seal / open (store-injectable — the self-check drives these directly)

    static func seal(_ plaintext: Data, to them: ProtocolAddress, as me: ProtocolAddress,
                     store: WorldSignalStore) throws -> Data {
        let sealed = try signalEncrypt(message: plaintext, for: them, localAddress: me,
                                       sessionStore: store, identityStore: store,
                                       context: WorldStoreContext())
        return frame(sealed)
    }

    /// Opens one framed ciphertext. Consumes the message key — call once.
    ///
    /// A peer that reinstalled arrives here as `untrustedIdentity`. Refusing it
    /// forever would brick the thread for a legitimate reinstall, so the stale
    /// identity and session are dropped and the open is retried once. The
    /// identity change is reported back to the caller rather than swallowed:
    /// it is exactly what a key substitution would also look like, and the
    /// in-thread notice (Phase E) is the trace the user gets.
    static func open(_ framed: Data, from them: ProtocolAddress, as me: ProtocolAddress,
                     store: WorldSignalStore,
                     identityChanged: (() -> Void)? = nil) throws -> Data {
        do {
            return try decrypt(framed, from: them, as: me, store: store)
        } catch SignalError.untrustedIdentity {
            store.forgetPeer(them)
            identityChanged?()
            // Only a PreKey message can rebuild a session from nothing; a
            // Whisper message from the new identity has no session left to
            // open against and stays unreadable until their next PreKey
            // message re-establishes one. Retrying regardless keeps that
            // distinction in libsignal rather than in a guess here.
            return try decrypt(framed, from: them, as: me, store: store)
        }
    }

    private static func decrypt(_ framed: Data, from them: ProtocolAddress, as me: ProtocolAddress,
                                store: WorldSignalStore) throws -> Data {
        let (type, body) = try unframe(framed)
        let context = WorldStoreContext()
        switch type {
        case .preKey:
            return try signalDecryptPreKey(
                message: try PreKeySignalMessage(bytes: body),
                from: them, localAddress: me,
                sessionStore: store, identityStore: store,
                preKeyStore: store, signedPreKeyStore: store, kyberPreKeyStore: store,
                context: context)
        case .whisper:
            return try signalDecrypt(
                message: try SignalMessage(bytes: body),
                from: them, to: me,
                sessionStore: store, identityStore: store,
                context: context)
        default:
            // Sender-key (groups) and plaintext-content messages: nothing this
            // build sends, so a build that does is newer than this one.
            throw SessionError.malformedCiphertext
        }
    }

    // MARK: Downgrade high-water mark (Phase E)
    //
    // Phase C left a hole and said so: a v1 envelope was still accepted on a
    // thread that already had a session, because refusing it would have fired
    // legitimately during rollout — a peer keeps sending v1 until they have
    // fetched our bundle, and we may have established a session toward them
    // first.
    //
    // The precise mark is not "we have a session" but "**they** have sent us a
    // sealed message". That can only happen once they hold our bundle, and from
    // that moment they have a session of their own and will never send v1
    // again. So a v1 envelope from such a peer is not a straggler; it is
    // someone else writing to the row. It is refused.
    //
    // Phase G moved the mark into the shared defaults suite: the extension
    // enforces the same rule, and a mark only one process could see would let a
    // downgrade through whichever process happened to open the message.

    private static let sealedPeersKey = "world.e2ee.sealedPeers"

    private static var sealedPeers: Set<String> {
        // Reads the old per-app suite too, once, so the mark survives the move.
        // Losing it would silently re-open the downgrade window for every peer
        // already talking to this device.
        var peers = Set(WorldAppGroup.defaults.stringArray(forKey: sealedPeersKey) ?? [])
        if let legacy = UserDefaults.standard.stringArray(forKey: sealedPeersKey), !legacy.isEmpty {
            peers.formUnion(legacy)
            WorldAppGroup.defaults.set(Array(peers), forKey: sealedPeersKey)
            UserDefaults.standard.removeObject(forKey: sealedPeersKey)
        }
        return peers
    }

    static func recordSealedMessage(from peer: UUID) {
        let id = peer.uuidString.lowercased()
        var peers = sealedPeers
        guard peers.insert(id).inserted else { return }
        WorldAppGroup.defaults.set(Array(peers), forKey: sealedPeersKey)
    }

    /// True once this peer has ever delivered a sealed message to this device.
    static func hasSentSealed(_ peer: UUID) -> Bool {
        sealedPeers.contains(peer.uuidString.lowercased())
    }

    static func forgetSealedPeers() {
        WorldAppGroup.defaults.removeObject(forKey: sealedPeersKey)
        UserDefaults.standard.removeObject(forKey: sealedPeersKey)
    }

    /// Whether this device already holds a ratchet with someone. A thread that
    /// has one may never fall back to the readable envelope — see the downgrade
    /// rule in `WorldEnvelope`.
    static func hasSession(with peer: UUID) -> Bool {
        guard let them = try? address(for: peer),
              let record = try? WorldSignalStore.shared.loadSession(for: them,
                                                                    context: WorldStoreContext())
        else { return false }
        return record != nil
    }
}
