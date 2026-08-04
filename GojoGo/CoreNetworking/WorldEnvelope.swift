import Foundation

// MARK: - GojoMessages E2EE envelope (Phase A — see E2EE-PLAN.md)
//
// The wire's `kind` becomes "encrypted" and everything the server used to read
// — kind, text, the quoted-reply card — travels inside one opaque payload. The
// server stores and forwards it blind; a message with no envelope is legacy
// plaintext and renders forever.
//
// Two things deliberately stay OUTSIDE the envelope:
//  - Media *URLs*: the server reference-counts uploads by URL. What's behind
//    the URL gets encrypted in Phase D; the pointer itself stays visible.
//  - Polls: the server tallies votes by mutating the stored poll, which an
//    opaque body cannot support. Polls (and groups) are outside v1 scope.
//
// Phase C (2026-08-04) put a Double Ratchet behind it. `envelopeVersion` is
// what says which: **1** is the Phase A envelope, opaque to the server's
// *rendering* but readable by anyone holding the row; **2** is sealed to a
// libsignal session and readable only by the two devices. Both versions stay
// live on the wire on purpose — a thread goes to 2 only once the peer has
// published a key bundle, and a thread that never does keeps working at 1.

/// What travels inside `cipherBody`, version 1. Grows by adding optionals —
/// never by renaming: an old build must be able to decode a new payload and
/// simply ignore what it doesn't know.
struct WorldEnvelopePayload: Codable {
    /// Wire kind of the *content* ("text", "emoji", "photo", …) — the outer
    /// message's kind is just "encrypted".
    var kind: String
    var text: String?
    /// Quoted-reply card, self-contained: the receiver must not need the
    /// server's copy of the replied-to message to draw the quote.
    var replyAuthorId: UUID?
    var replyAuthorName: String?
    var replyPreview: String?
    /// Voice-note / video length label ("0:42").
    var durationLabel: String?
    /// A shared pin's real coordinates.
    var latitude: Double?
    var longitude: Double?
    var fileName: String?
    var fileMeta: String?
    /// Phase D: `mediaURL -> base64 AES-256-GCM key`, one per attachment.
    ///
    /// Keyed by URL rather than positional, because a carousel's poster and its
    /// movie are two files on one item and the wire order is not something the
    /// receiver should have to trust. Absent on every message before Phase D
    /// and on any message whose attachments went up in the clear — the receiver
    /// reads the bytes verbatim then, which is what keeps old media rendering.
    var mediaKeys: [String: String]?
}

enum WorldEnvelope {
    /// Phase A: the payload travels as-is. The server can't *render* it, but it
    /// isn't encrypted — anyone with the stored row can read it. Still written
    /// for a peer who has never published a key bundle, so a thread with an old
    /// build (or a fresh install that hasn't synced keys yet) keeps working.
    static let plaintextVersion = 1
    /// Phase C: the payload is sealed to a libsignal session. Readable by the
    /// two devices and nothing else.
    static let sealedVersion = 2
    /// The highest version this build can open. A payload above it renders as
    /// "needs a newer version" — real, undamaged, just not representable here.
    static let version = sealedVersion

    /// Whether outgoing 1:1 content is wrapped.
    ///
    /// Requires the envelope-aware backend: one that doesn't know `cipherBody`
    /// drops the field silently (Jackson), storing an envelope with *no body*.
    /// Flipped on 2026-08-04 after the `fecbce2` deploy went green and an
    /// envelope message round-tripped through the live API.
    static let sendingEnabled = true

    enum EnvelopeError: Error {
        /// A payload from a build newer than this one. The message is real and
        /// undamaged — this build just can't represent it.
        case unsupportedVersion(Int)
        case malformed
        /// A readable envelope arrived from a peer who has already sent sealed
        /// ones. They cannot have gone back — they hold our bundle and a
        /// session. Something else wrote this row. (Phase E.)
        case downgraded
    }

    /// The Phase A body: encoded, not encrypted.
    ///
    /// Only legitimate when the peer has published no key bundle. A thread that
    /// already has a session must never come back here — quietly answering a
    /// transient failure with a readable body is precisely the downgrade an
    /// attacker would ask for, so `envelopeBody` refuses to send instead.
    static func sealPlaintext(_ payload: WorldEnvelopePayload) throws -> (version: Int, body: String) {
        (plaintextVersion, try JSONEncoder().encode(payload).base64EncodedString())
    }

    /// The Phase C body: sealed to the peer's ratchet, establishing the session
    /// from the key directory if this is the first message.
    @MainActor
    static func seal(_ payload: WorldEnvelopePayload, to peer: UUID) async throws
        -> (version: Int, body: String) {
        let plain = try JSONEncoder().encode(payload)
        let sealed = try await WorldSignalSession.seal(plain, to: peer)
        return (sealedVersion, sealed.base64EncodedString())
    }

    /// Opens a body of either version. `sender` is the *peer's* profile id —
    /// sessions are per-peer, not per-conversation.
    ///
    /// For v2 this consumes the message key: never call it twice on the same
    /// body. `WorldEnvelopeVault` is what guarantees the caller doesn't.
    @MainActor
    static func open(version: Int, body: String, from sender: UUID,
                     identityChanged: (() -> Void)? = nil) throws -> WorldEnvelopePayload {
        guard version <= Self.version else { throw EnvelopeError.unsupportedVersion(version) }
        guard let sealed = Data(base64Encoded: body) else { throw EnvelopeError.malformed }
        guard version >= sealedVersion || !WorldSignalSession.hasSentSealed(sender) else {
            // Phase E: this peer has sealed to us before, so they cannot have
            // lost the ability to. Reading it anyway would make stripping the
            // encryption a matter of rewriting one field.
            throw EnvelopeError.downgraded
        }
        let plain = version >= sealedVersion
            ? try WorldSignalSession.open(sealed, from: sender, identityChanged: identityChanged)
            : sealed
        if version >= sealedVersion { WorldSignalSession.recordSealedMessage(from: sender) }
        return try JSONDecoder().decode(WorldEnvelopePayload.self, from: plain)
    }
}
