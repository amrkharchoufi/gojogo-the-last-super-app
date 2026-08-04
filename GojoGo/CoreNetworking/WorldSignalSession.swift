import Foundation
import LibSignalClient

// MARK: - Double Ratchet sessions, the app's half (Phase C — see E2EE-PLAN.md)
//
// The protocol itself — addresses, framing, seal, open, the downgrade mark —
// lives in `GojoGoShared/WorldSignalSessionCore.swift`, compiled into the
// notification extension as well (Phase G). What stays here is everything that
// needs the app to exist: who is signed in, and the network round trip to the
// key directory that turns a stranger into a session.
//
// The extension deliberately has none of this. It can open a message from a
// peer it already has a session with, and that is all it can do — an extension
// that could establish sessions would be an extension that could consume a
// one-time prekey and mint an identity, in a process that gets killed for
// running 24 MB over.

extension WorldSignalSession {

    @MainActor
    private static var myAddress: ProtocolAddress? {
        guard let id = MessagingStore.shared.myProfileId ?? SocialStore.shared.myProfileId
        else { return nil }
        return try? address(for: id)
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
    ///
    /// Under the ratchet lock: sealing advances the same session record the
    /// notification extension may be decrypting into (Phase G), and a session
    /// written from two processes at once loses every later message from that
    /// peer.
    @MainActor
    static func seal(_ plaintext: Data, to peer: UUID) async throws -> Data {
        guard let me = myAddress else { throw SessionError.identityUnavailable }
        let them = try address(for: peer)
        let store = WorldSignalStore.shared
        if try store.loadSession(for: them, context: WorldStoreContext()) == nil {
            // Outside the lock on purpose — this is a network round trip, and
            // holding a cross-process lock across one would stall the extension
            // for as long as the key directory takes to answer.
            try await establishSession(with: them, store: store)
        }
        return try WorldRatchetLock.withLock {
            try seal(plaintext, to: them, as: me, store: store)
        }
    }

    // Receiving no longer has an entry point here: it goes through
    // `WorldEnvelopeOpener`, which takes the cross-process lock and the vault
    // with it, and which the extension calls too.

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
        try WorldRatchetLock.withLock {
            do {
                try processPreKeyBundle(bundle, for: them, ourAddress: me,
                                        sessionStore: store, identityStore: store,
                                        context: WorldStoreContext())
            } catch SignalError.untrustedIdentity {
                // A reinstall, or a substitution. Same reasoning as `open`:
                // refusing forever brings the thread down permanently, so the
                // stale material goes and the bundle is accepted once.
                store.forgetPeer(them)
                try processPreKeyBundle(bundle, for: them, ourAddress: me,
                                        sessionStore: store, identityStore: store,
                                        context: WorldStoreContext())
            }
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
