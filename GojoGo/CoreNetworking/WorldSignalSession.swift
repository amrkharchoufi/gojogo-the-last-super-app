import Foundation
import LibSignalClient

// MARK: - Double Ratchet sessions (E2EE Phase C — see E2EE-PLAN.md)
//
// The seam Phase A left behind: `WorldEnvelope` used to hand its payload to an
// identity transform, and now hands it here. Everything around it — the wire
// shape, the local archive, previews, push — was built and verified while the
// payload was still readable, so a blank bubble in Phase C has exactly one
// suspect: this file.
//
// Three things are worth knowing before reading further.
//
// **A ciphertext decrypts exactly once, ever.** The message key is deleted on
// use, and that deletion *is* forward secrecy. So nothing may call `open` twice
// on the same bytes — the second call throws `duplicatedMessage` and the
// message is gone for good. `WorldEnvelopeVault` is what makes that safe: the
// opened payload is recorded the first time and served from disk afterwards.
//
// **A sender cannot read its own ciphertext.** It is sealed to the peer's
// ratchet, not ours. Our own sent messages are readable only because the vault
// records the payload at seal time, under the client id.
//
// **Sessions are per *peer*, not per conversation.** Phase A guessed the
// opposite; the address here is a profile id plus a device id, which is why
// the day-one `deviceId` rule exists and why multi-device is schema-ready.

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

        var errorDescription: String? {
            switch self {
            case .peerHasNoKeys: return "That contact hasn't set up encryption yet."
            case .identityUnavailable: return "Encryption isn't ready yet."
            case .malformedCiphertext: return "The message body was damaged."
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
    /// it is exactly what a key substitution would also look like, and until
    /// safety numbers ship (Phase E) the in-thread notice is the only trace a
    /// user gets.
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

    // MARK: App-level entry points

    @MainActor
    private static var myAddress: ProtocolAddress? {
        guard let id = MessagingStore.shared.myProfileId ?? SocialStore.shared.myProfileId
        else { return nil }
        return try? address(for: id)
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

    /// Whether this message can be sealed to `peer`, establishing the session
    /// now if there isn't one yet.
    ///
    /// Exists for Phase D. Media is encrypted *before* upload, which happens
    /// well before `envelopeBody` decides which envelope version to write — so
    /// the send path has to know the answer up front. Asking here also means
    /// the session is already open by the time the seal runs, rather than being
    /// established twice.
    ///
    /// False means only one thing: the peer has published no bundle at all. Any
    /// other failure throws, because "couldn't tell" must never be answered by
    /// sending in the clear.
    @MainActor
    static func canSeal(to peer: UUID) async throws -> Bool {
        let them = try address(for: peer)
        let store = WorldSignalStore.shared
        if try store.loadSession(for: them, context: WorldStoreContext()) != nil { return true }
        do {
            try await establishSession(with: them, store: store)
            return true
        } catch SessionError.peerHasNoKeys {
            return false
        }
    }

    /// Seals for a peer, establishing the session from the key directory first
    /// if there isn't one. Throws `peerHasNoKeys` when the peer has never
    /// published — the only case a caller may answer with a readable envelope.
    @MainActor
    static func seal(_ plaintext: Data, to peer: UUID) async throws -> Data {
        guard let me = myAddress else { throw SessionError.identityUnavailable }
        let them = try address(for: peer)
        let store = WorldSignalStore.shared
        if try store.loadSession(for: them, context: WorldStoreContext()) == nil {
            try await establishSession(with: them, store: store)
        }
        return try seal(plaintext, to: them, as: me, store: store)
    }

    /// Opens a received body. Synchronous on purpose: decryption never needs
    /// the network, so the render path doesn't gain a suspend point.
    @MainActor
    static func open(_ framed: Data, from peer: UUID,
                     identityChanged: (() -> Void)? = nil) throws -> Data {
        guard let me = myAddress else { throw SessionError.identityUnavailable }
        return try open(framed, from: try address(for: peer), as: me,
                        store: WorldSignalStore.shared, identityChanged: identityChanged)
    }

    /// X3DH: fetch the peer's published bundle and turn it into a session.
    ///
    /// The GET **consumes** one of their one-time prekeys server-side, so this
    /// runs once per peer and only when there is no session to reuse.
    @MainActor
    private static func establishSession(with them: ProtocolAddress,
                                         store: WorldSignalStore) async throws {
        guard let me = myAddress else { throw SessionError.identityUnavailable }
        guard let peer = UUID(uuidString: them.name) else { throw SessionError.identityUnavailable }
        let dto: WorldKeyBundleDTO
        do {
            dto = try await MessagingStore.shared.keyBundle(for: peer, deviceId: Int(deviceId))
        } catch APIClient.APIError.http(let status, _) where status == 404 {
            throw SessionError.peerHasNoKeys
        }
        let bundle = try Self.bundle(from: dto)
        do {
            try processPreKeyBundle(bundle, for: them, ourAddress: me,
                                    sessionStore: store, identityStore: store,
                                    context: WorldStoreContext())
        } catch SignalError.untrustedIdentity {
            // A reinstall, or a substitution. Same reasoning as `open`: refusing
            // forever brings the thread down permanently, so the stale material
            // goes and the bundle is accepted once.
            store.forgetPeer(them)
            try processPreKeyBundle(bundle, for: them, ourAddress: me,
                                    sessionStore: store, identityStore: store,
                                    context: WorldStoreContext())
        }
    }

    /// Rebuilds a `PreKeyBundle` from the directory's JSON. A bundle with no
    /// one-time prekey is valid, not an error: the pool can legitimately be
    /// empty, and X3DH degrades to the signed prekey (weaker replay properties
    /// for the first message only, which is why the publisher tops the pool up).
    static func bundle(from dto: WorldKeyBundleDTO) throws -> PreKeyBundle {
        guard let identityBytes = Data(base64Encoded: dto.identityKey),
              let signedPublic = Data(base64Encoded: dto.signedPreKey.publicKey),
              let signedSignature = Data(base64Encoded: dto.signedPreKey.signature),
              let kyberPublic = Data(base64Encoded: dto.kyberPreKey.publicKey),
              let kyberSignature = Data(base64Encoded: dto.kyberPreKey.signature)
        else { throw SessionError.malformedCiphertext }

        let identity = try IdentityKey(bytes: identityBytes)
        let signed = try PublicKey(signedPublic)
        let kyber = try KEMPublicKey(kyberPublic)

        if let oneTime = dto.oneTimePreKey, let oneTimeBytes = Data(base64Encoded: oneTime.publicKey) {
            return try PreKeyBundle(
                registrationId: UInt32(dto.registrationId),
                deviceId: UInt32(dto.deviceId),
                prekeyId: UInt32(oneTime.id),
                prekey: try PublicKey(oneTimeBytes),
                signedPrekeyId: UInt32(dto.signedPreKey.id),
                signedPrekey: signed,
                signedPrekeySignature: signedSignature,
                identity: identity,
                kyberPrekeyId: UInt32(dto.kyberPreKey.id),
                kyberPrekey: kyber,
                kyberPrekeySignature: kyberSignature)
        }
        return try PreKeyBundle(
            registrationId: UInt32(dto.registrationId),
            deviceId: UInt32(dto.deviceId),
            signedPrekeyId: UInt32(dto.signedPreKey.id),
            signedPrekey: signed,
            signedPrekeySignature: signedSignature,
            identity: identity,
            kyberPrekeyId: UInt32(dto.kyberPreKey.id),
            kyberPrekey: kyber,
            kyberPrekeySignature: kyberSignature)
    }
}
