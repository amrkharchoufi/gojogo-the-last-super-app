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
// The cipher below is an identity transform on purpose. Phase A proves the
// envelope, the migration story, previews and push with every payload still
// readable — so a blank bubble has exactly one suspect. Phase C swaps this
// protocol's implementation for libsignal sessions and changes nothing else.

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
}

/// Seals and opens envelope bodies. One conversation-scoped transform, so the
/// Phase C swap to libsignal (whose sessions are per-peer) is a drop-in.
protocol WorldMessageCipher {
    /// "none" for the Phase A identity transform; a real cipher type later.
    var cipherType: String { get }
    func seal(_ plaintext: Data, conversationId: UUID) throws -> Data
    func open(_ ciphertext: Data, conversationId: UUID) throws -> Data
}

/// Phase A: the identity transform. Not encryption — scaffolding that lets the
/// entire envelope path ship and be verified while payloads stay readable.
struct WorldPlaintextCipher: WorldMessageCipher {
    let cipherType = "none"
    func seal(_ plaintext: Data, conversationId: UUID) throws -> Data { plaintext }
    func open(_ ciphertext: Data, conversationId: UUID) throws -> Data { ciphertext }
}

enum WorldEnvelope {
    /// The one version this build writes and the highest it can read.
    static let version = 1

    /// Whether outgoing 1:1 content is wrapped.
    ///
    /// **Off until the envelope-aware backend is deployed.** The live backend
    /// doesn't know `cipherBody`; Jackson drops unknown fields silently, so an
    /// envelope sent to it stores as `kind: "encrypted"` with *no body* — the
    /// content never reaches the server at all. Flip to `true` in the same
    /// change that confirms the backend rollout; the read path below is
    /// already live either way, so old and new builds interoperate.
    static let sendingEnabled = false

    static var cipher: WorldMessageCipher = WorldPlaintextCipher()

    enum EnvelopeError: Error {
        /// A payload from a build newer than this one. The message is real and
        /// undamaged — this build just can't represent it.
        case unsupportedVersion(Int)
        case malformed
    }

    static func seal(_ payload: WorldEnvelopePayload, conversationId: UUID) throws -> String {
        let plain = try JSONEncoder().encode(payload)
        let sealed = try cipher.seal(plain, conversationId: conversationId)
        return sealed.base64EncodedString()
    }

    static func open(version: Int, body: String, conversationId: UUID) throws -> WorldEnvelopePayload {
        guard version <= Self.version else { throw EnvelopeError.unsupportedVersion(version) }
        guard let sealed = Data(base64Encoded: body) else { throw EnvelopeError.malformed }
        let plain = try cipher.open(sealed, conversationId: conversationId)
        return try JSONDecoder().decode(WorldEnvelopePayload.self, from: plain)
    }
}
