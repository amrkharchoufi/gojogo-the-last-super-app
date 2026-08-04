#if DEBUG
import Foundation
import LibSignalClient

// MARK: - Protocol loopback self-check (E2EE Phase B → C gate)
//
// Runs the complete X3DH + Double Ratchet handshake between two isolated
// instances of the *real* `WorldSignalStore`, in-process. Nothing here talks to
// the network: the "directory" is a bundle passed hand to hand.
//
// This exists because of what Phase C's failure mode costs. A ratchet deletes
// each message key the moment it's used — that deletion is forward secrecy —
// so a message encrypted through a subtly wrong store is not "broken", it is
// **permanently unreadable, by anyone, forever**. Two-party testing needs a
// second account, which we don't have; two-*store* testing needs nothing but
// a temp directory, and exercises the same five protocol implementations the
// live path will use.
//
// What it proves, in order:
//   1. A published bundle round-trips into a session (`processPreKeyBundle`)
//   2. The first message encrypts as a PreKey message and decrypts through
//      `signalDecryptPreKey`, consuming the one-time prekey
//   3. The session ratchets — a reply from the other side decrypts
//   4. The ratchet advances — a second message uses fresh keys and still opens
//   5. Ciphertext is genuinely opaque (the plaintext is not sitting inside it)
//   6. State survives a store *reopen* — new instances over the same directory
//      decrypt correctly, which is what the app does on every cold start

enum WorldSignalSelfCheck {

    struct Failure: Error, CustomStringConvertible {
        let step: String
        var description: String { "libsignal self-check failed at: \(step)" }
    }

    /// Runs the loopback and logs a one-line verdict. Safe to call at launch.
    static func run() {
        do {
            try loopback()
            print("✅ libsignal self-check passed — X3DH handshake, ratchet, "
                  + "persistence and opacity all verified")
        } catch {
            print("❌ \(error)")
        }
    }

    private static func loopback() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("signal-selfcheck-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }

        let aliceRoot = scratch.appendingPathComponent("alice", isDirectory: true)
        let bobRoot = scratch.appendingPathComponent("bob", isDirectory: true)

        var alice = WorldSignalStore(root: aliceRoot, usesKeychain: false)
        var bob = WorldSignalStore(root: bobRoot, usesKeychain: false)
        let ctx = WorldStoreContext()

        let aliceAddress = try ProtocolAddress(name: UUID().uuidString, deviceId: 1)
        let bobAddress = try ProtocolAddress(name: UUID().uuidString, deviceId: 1)

        // --- Bob publishes, exactly as WorldKeyPublisher does -------------
        let (bobIdentity, bobRegistrationId) = try bob.ensureIdentity()
        let bobSigned = try bob.currentOrMintSignedPreKey(identity: bobIdentity)
        let bobKyber = try bob.currentOrMintKyberPreKey(identity: bobIdentity)
        guard let bobOneTime = try bob.mintOneTimePreKeys(count: 1).first else {
            throw Failure(step: "minting Bob's one-time prekey")
        }

        // --- Alice turns that bundle into a session ------------------------
        let bundle = try PreKeyBundle(
            registrationId: bobRegistrationId,
            deviceId: 1,
            prekeyId: bobOneTime.id,
            prekey: try bobOneTime.publicKey(),
            signedPrekeyId: bobSigned.id,
            signedPrekey: try bobSigned.publicKey(),
            signedPrekeySignature: bobSigned.signature,
            identity: bobIdentity.identityKey,
            kyberPrekeyId: bobKyber.id,
            kyberPrekey: try bobKyber.publicKey(),
            kyberPrekeySignature: bobKyber.signature)

        try processPreKeyBundle(
            bundle, for: bobAddress, ourAddress: aliceAddress,
            sessionStore: alice, identityStore: alice, context: ctx)

        guard try alice.loadSession(for: bobAddress, context: ctx) != nil else {
            throw Failure(step: "session not stored after processPreKeyBundle")
        }

        // --- 1. Alice → Bob, the PreKey message ----------------------------
        let opener = "the first sealed message"
        let sealed = try signalEncrypt(
            message: Data(opener.utf8), for: bobAddress, localAddress: aliceAddress,
            sessionStore: alice, identityStore: alice, context: ctx)

        guard sealed.messageType == .preKey else {
            throw Failure(step: "first message should be a PreKey message, got \(sealed.messageType)")
        }
        // Opacity: the plaintext must not be lying inside the ciphertext.
        if sealed.serialize().range(of: Data(opener.utf8)) != nil {
            throw Failure(step: "plaintext found inside ciphertext")
        }

        let openedData = try signalDecryptPreKey(
            message: try PreKeySignalMessage(bytes: sealed.serialize()),
            from: aliceAddress, localAddress: bobAddress,
            sessionStore: bob, identityStore: bob,
            preKeyStore: bob, signedPreKeyStore: bob, kyberPreKeyStore: bob,
            context: ctx)
        guard String(data: openedData, encoding: .utf8) == opener else {
            throw Failure(step: "PreKey message did not round-trip")
        }

        // The one-time prekey must be spent — reuse would break the guarantee.
        if (try? bob.loadPreKey(id: bobOneTime.id, context: ctx)) != nil {
            throw Failure(step: "one-time prekey survived decryption")
        }

        // --- 2. Bob → Alice, proving the session is bidirectional ----------
        let reply = "and the reply that ratchets"
        let sealedReply = try signalEncrypt(
            message: Data(reply.utf8), for: aliceAddress, localAddress: bobAddress,
            sessionStore: bob, identityStore: bob, context: ctx)
        guard sealedReply.messageType == .whisper else {
            throw Failure(step: "reply should be a Whisper message, got \(sealedReply.messageType)")
        }
        let openedReply = try signalDecrypt(
            message: try SignalMessage(bytes: sealedReply.serialize()),
            from: bobAddress, to: aliceAddress,
            sessionStore: alice, identityStore: alice, context: ctx)
        guard String(data: openedReply, encoding: .utf8) == reply else {
            throw Failure(step: "reply did not round-trip")
        }

        // --- 3. Reopen both stores: cold-start behaviour --------------------
        // New instances over the same directories — if session persistence were
        // wrong, everything above would still pass and the app would break on
        // the second launch instead.
        alice = WorldSignalStore(root: aliceRoot, usesKeychain: false)
        bob = WorldSignalStore(root: bobRoot, usesKeychain: false)

        let third = "sent after a cold start"
        let sealedThird = try signalEncrypt(
            message: Data(third.utf8), for: bobAddress, localAddress: aliceAddress,
            sessionStore: alice, identityStore: alice, context: ctx)
        let openedThird = try signalDecrypt(
            message: try SignalMessage(bytes: sealedThird.serialize()),
            from: aliceAddress, to: bobAddress,
            sessionStore: bob, identityStore: bob, context: ctx)
        guard String(data: openedThird, encoding: .utf8) == third else {
            throw Failure(step: "message after store reopen did not round-trip")
        }

        // --- 4. Distinct ciphertexts for identical plaintext ---------------
        // The ratchet must move: same text twice must not produce same bytes.
        let repeated = "same words twice"
        let firstCopy = try signalEncrypt(
            message: Data(repeated.utf8), for: bobAddress, localAddress: aliceAddress,
            sessionStore: alice, identityStore: alice, context: ctx)
        let secondCopy = try signalEncrypt(
            message: Data(repeated.utf8), for: bobAddress, localAddress: aliceAddress,
            sessionStore: alice, identityStore: alice, context: ctx)
        guard firstCopy.serialize() != secondCopy.serialize() else {
            throw Failure(step: "ratchet did not advance — identical ciphertexts")
        }
        // Out-of-order delivery: open the *second* one first. This is the case
        // a dropped socket actually produces, and the one a naive store gets
        // wrong by discarding skipped keys.
        _ = try signalDecrypt(
            message: try SignalMessage(bytes: secondCopy.serialize()),
            from: aliceAddress, to: bobAddress,
            sessionStore: bob, identityStore: bob, context: ctx)
        let recovered = try signalDecrypt(
            message: try SignalMessage(bytes: firstCopy.serialize()),
            from: aliceAddress, to: bobAddress,
            sessionStore: bob, identityStore: bob, context: ctx)
        guard String(data: recovered, encoding: .utf8) == repeated else {
            throw Failure(step: "out-of-order message did not decrypt")
        }
    }
}
#endif
