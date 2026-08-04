import Foundation

// MARK: - Envelope, the app's half (Phase A/C — see E2EE-PLAN.md)
//
// The payload shape, the version constants and the rules for opening one live
// in `GojoGoShared/WorldEnvelopeCore.swift`, because the notification extension
// opens envelopes too (Phase G) and there must be exactly one implementation of
// "what a v1 body is, what a v2 body is, and when a readable one is a
// downgrade".
//
// What is left here is the half that needs the app: sealing asks the key
// directory for a bundle over the network, which the extension neither can nor
// should do.

extension WorldEnvelope {

    /// The Phase C body: sealed to the peer's ratchet, establishing the session
    /// from the key directory if this is the first message.
    @MainActor
    static func seal(_ payload: WorldEnvelopePayload, to peer: UUID) async throws
        -> (version: Int, body: String) {
        let plain = try JSONEncoder().encode(payload)
        let sealed = try await WorldSignalSession.seal(plain, to: peer)
        return (sealedVersion, sealed.base64EncodedString())
    }
}
