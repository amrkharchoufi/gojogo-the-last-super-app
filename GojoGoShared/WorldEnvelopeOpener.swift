import Foundation

// MARK: - Opening a message exactly once, from either process (Phase G)
//
// Before Phase G the "open exactly once" rule had one enforcer per concern: the
// vault remembered what had been opened, and the app was the only thing asking.
// The notification extension breaks the second half of that — it receives the
// same message the socket is delivering, at the same moment, with the same
// session files underneath it.
//
// So the sequence below is the whole atom, and both processes run this exact
// code inside `WorldRatchetLock`:
//
//     look in the vault  →  ask libsignal  →  write the session  →  bank it
//
// Split any part of that out of the lock and the two failure modes from the
// lock's own comment come back: a duplicate decrypt that loses the message, or
// a session record written from two sides that loses every *later* message from
// that peer.
//
// The vault lookups are also where our own outgoing messages resolve — sealed
// to the peer's ratchet, so this device could never decrypt them, and readable
// only because `envelopeBody` banked the payload under the client id at seal
// time.

enum WorldEnvelopeOpener {

    /// Returns the payload for one envelope message, decrypting only if nobody
    /// has already. `me` is this device's profile id; `sender` the peer's.
    ///
    /// Throws exactly what `WorldEnvelope.open` throws — the caller decides what
    /// a failure looks like, because the two callers want opposite things: the
    /// app renders a bubble that explains itself, and the extension leaves the
    /// server's generic banner alone.
    static func payload(version: Int, body: String,
                        messageId: UUID, clientId: UUID?, conversationId: UUID,
                        from sender: UUID, as me: UUID,
                        store: WorldSignalStore = .shared,
                        identityChanged: (() -> Void)? = nil) throws -> WorldEnvelopePayload {
        // Fast path, deliberately outside the lock: re-rendering a thread asks
        // this question once per message per pass, and a message that is
        // already open needs no ratchet and must not queue behind one. Checked
        // again inside the lock below — this is a shortcut, not the decision.
        // Only the message id, so that the client-id case still takes the lock
        // and gets re-keyed there rather than being looked up twice forever.
        if let banked = WorldEnvelopeVault.shared.payload(for: messageId, in: conversationId) {
            return banked
        }
        return try WorldRatchetLock.withLock {
            let vault = WorldEnvelopeVault.shared
            if let banked = vault.payload(for: messageId, in: conversationId) {
                return banked
            }
            // Our own message coming back as an echo, or a fetched page after a
            // relaunch: banked under the client id at seal time, re-keyed onto
            // the server's id here so the next lookup is a straight hit.
            if let clientId, let banked = vault.payload(for: clientId, in: conversationId) {
                vault.store(banked, for: messageId, in: conversationId)
                return banked
            }
            let payload = try WorldEnvelope.open(version: version, body: body,
                                                 from: sender, as: me, store: store,
                                                 identityChanged: identityChanged)
            // Inside the lock, and on disk before it is released. This is the
            // record that stops the other process spending a key that is
            // already gone.
            vault.store(payload, for: messageId, in: conversationId)
            return payload
        }
    }

    /// The already-opened payload, if there is one, without ever asking
    /// libsignal. Used where a decrypt would be wrong or pointless — the
    /// extension's first look, and any render path that must not consume a key.
    static func bankedPayload(messageId: UUID, clientId: UUID?,
                              conversationId: UUID) -> WorldEnvelopePayload? {
        let vault = WorldEnvelopeVault.shared
        if let banked = vault.payload(for: messageId, in: conversationId) { return banked }
        guard let clientId else { return nil }
        return vault.payload(for: clientId, in: conversationId)
    }
}
