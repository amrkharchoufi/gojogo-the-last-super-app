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
//
// Phase C added a second half (`framing`), which drives the code the app
// actually calls rather than libsignal directly:
//   7. A directory bundle DTO rebuilds into a working `PreKeyBundle`
//   8. `WorldSignalSession`'s frame byte tags PreKey and Whisper correctly —
//      get this wrong and every message is unreadable in one direction
//   9. Opening the same ciphertext twice really does fail, which is the fact
//      `WorldEnvelopeVault` exists to work around
//  10. A peer who reinstalled is recovered from, not refused forever

enum WorldSignalSelfCheck {

    struct Failure: Error, CustomStringConvertible {
        let step: String
        var description: String { "libsignal self-check failed at: \(step)" }
    }

    /// Runs the loopback and logs a one-line verdict. Safe to call at launch.
    static func run() {
        do {
            try loopback()
            print("✅ E2EE self-check passed — X3DH handshake, ratchet, persistence, "
                  + "opacity, message framing, replay fatality, reinstall recovery "
                  + "and per-file media crypto all verified")
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

        // --- 5. The Phase C code path itself ------------------------------
        // Everything above calls libsignal directly. The app calls
        // `WorldSignalSession`, which adds the framing that tells a receiver
        // which of the two message types it is holding — the one piece of
        // Phase C that is ours rather than Signal's, and the one that turns
        // every message unreadable if it is wrong.
        try framing()
        try mediaCrypto()
    }

    /// Phase D: the per-file media transform. Cheap to check and expensive to
    /// get wrong — an attachment encrypted with a key nobody kept is a photo
    /// that is gone, and unlike the ratchet there is no protocol to blame.
    private static func mediaCrypto() throws {
        // Not a JPEG, but neither is a JPEG to AES — what matters is that the
        // bytes are recognisable if they ever leak through unencrypted.
        let original = Data("PNG\u{0}this is the picture itself".utf8)
        let (ciphertext, key) = try WorldMediaCrypto.seal(original)

        if ciphertext.range(of: original) != nil {
            throw Failure(step: "media plaintext found inside the uploaded bytes")
        }
        guard try WorldMediaCrypto.open(ciphertext, key: key) == original else {
            throw Failure(step: "media did not round-trip")
        }
        // Two files must never share a key: the whole point of per-file keys is
        // that leaking one attachment leaks exactly one attachment.
        let (_, otherKey) = try WorldMediaCrypto.seal(original)
        guard otherKey != key else {
            throw Failure(step: "two files were sealed with the same key")
        }
        if (try? WorldMediaCrypto.open(ciphertext, key: otherKey)) != nil {
            throw Failure(step: "media opened with the wrong key")
        }
        // GCM's tag is the reason a rewritten CDN object fails loudly instead
        // of decoding to something subtly different.
        var tampered = ciphertext
        tampered[tampered.count - 1] ^= 0x01
        if (try? WorldMediaCrypto.open(tampered, key: key)) != nil {
            throw Failure(step: "tampered media still opened — the GCM tag is not being checked")
        }
    }

    /// Drives the real `seal`/`open` the send and receive paths use, over two
    /// fresh stores whose first message must therefore be a PreKey message.
    private static func framing() throws {
        // A fresh pair, so the first framed message exercises the PreKey branch
        // rather than riding the session the checks above already opened.
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("signal-framing-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }

        let carol = WorldSignalStore(root: scratch.appendingPathComponent("carol"), usesKeychain: false)
        let dave = WorldSignalStore(root: scratch.appendingPathComponent("dave"), usesKeychain: false)
        let ctx = WorldStoreContext()
        let carolAddress = try ProtocolAddress(name: UUID().uuidString.lowercased(), deviceId: 1)
        let daveAddress = try ProtocolAddress(name: UUID().uuidString.lowercased(), deviceId: 1)

        let (daveIdentity, daveRegistrationId) = try dave.ensureIdentity()
        let daveSigned = try dave.currentOrMintSignedPreKey(identity: daveIdentity)
        let daveKyber = try dave.currentOrMintKyberPreKey(identity: daveIdentity)
        guard let daveOneTime = try dave.mintOneTimePreKeys(count: 1).first else {
            throw Failure(step: "minting Dave's one-time prekey")
        }

        // Through the same DTO shape the key directory returns, so a wrong
        // base64 field or a swapped signature fails here rather than in
        // production against a real bundle.
        let dto = try WorldKeyBundleDTO(
            registrationId: Int(daveRegistrationId),
            deviceId: 1,
            identityKey: daveIdentity.identityKey.serialize().base64EncodedString(),
            signedPreKey: WorldSignedPreKeyDTO(
                id: Int(daveSigned.id),
                publicKey: daveSigned.publicKey().serialize().base64EncodedString(),
                signature: daveSigned.signature.base64EncodedString()),
            kyberPreKey: WorldSignedPreKeyDTO(
                id: Int(daveKyber.id),
                publicKey: daveKyber.publicKey().serialize().base64EncodedString(),
                signature: daveKyber.signature.base64EncodedString()),
            oneTimePreKey: WorldPreKeyDTO(
                id: Int(daveOneTime.id),
                publicKey: daveOneTime.publicKey().serialize().base64EncodedString()))

        try processPreKeyBundle(
            try WorldSignalSession.bundle(from: dto),
            for: daveAddress, ourAddress: carolAddress,
            sessionStore: carol, identityStore: carol, context: ctx)

        let opener = "framed, sealed and delivered"
        let framed = try WorldSignalSession.seal(Data(opener.utf8), to: daveAddress,
                                                 as: carolAddress, store: carol)
        guard framed.first == CiphertextMessage.MessageType.preKey.rawValue else {
            throw Failure(step: "framed opener is not tagged as a PreKey message")
        }
        let opened = try WorldSignalSession.open(framed, from: carolAddress, as: daveAddress,
                                                 store: dave)
        guard String(data: opened, encoding: .utf8) == opener else {
            throw Failure(step: "framed message did not round-trip")
        }

        // The reply is a Whisper message, and must be tagged as one — a frame
        // that always claimed PreKey would still pass the check above.
        let reply = "and the whisper back"
        let framedReply = try WorldSignalSession.seal(Data(reply.utf8), to: carolAddress,
                                                      as: daveAddress, store: dave)
        guard framedReply.first == CiphertextMessage.MessageType.whisper.rawValue else {
            throw Failure(step: "framed reply is not tagged as a Whisper message")
        }
        guard try String(data: WorldSignalSession.open(framedReply, from: daveAddress,
                                                       as: carolAddress, store: carol),
                         encoding: .utf8) == reply else {
            throw Failure(step: "framed reply did not round-trip")
        }

        // Opening the same bytes twice is the mistake the whole vault exists to
        // prevent, so prove it really is fatal rather than merely discouraged.
        let replayed = try WorldSignalSession.seal(Data("once only".utf8), to: daveAddress,
                                                   as: carolAddress, store: carol)
        _ = try WorldSignalSession.open(replayed, from: carolAddress, as: daveAddress, store: dave)
        // Expected to throw: the message key was deleted on first use.
        let replayOpened = (try? WorldSignalSession.open(replayed, from: carolAddress,
                                                         as: daveAddress, store: dave)) != nil
        guard !replayOpened else {
            throw Failure(step: "a replayed ciphertext decrypted twice")
        }

        // A peer who reinstalled: new identity, new bundle, same address. The
        // send path must recover instead of refusing them forever.
        let dave2 = WorldSignalStore(root: scratch.appendingPathComponent("dave2"), usesKeychain: false)
        let (dave2Identity, dave2RegistrationId) = try dave2.ensureIdentity()
        let dave2Signed = try dave2.currentOrMintSignedPreKey(identity: dave2Identity)
        let dave2Kyber = try dave2.currentOrMintKyberPreKey(identity: dave2Identity)
        let dave2Bundle = try PreKeyBundle(
            registrationId: dave2RegistrationId, deviceId: 1,
            signedPrekeyId: dave2Signed.id, signedPrekey: dave2Signed.publicKey(),
            signedPrekeySignature: dave2Signed.signature,
            identity: dave2Identity.identityKey,
            kyberPrekeyId: dave2Kyber.id, kyberPrekey: dave2Kyber.publicKey(),
            kyberPrekeySignature: dave2Kyber.signature)
        let acceptedSilently = (try? processPreKeyBundle(
            dave2Bundle, for: daveAddress, ourAddress: carolAddress,
            sessionStore: carol, identityStore: carol, context: ctx)) != nil
        guard !acceptedSilently else {
            throw Failure(step: "a changed identity key was accepted silently")
        }
        // What the live path answers with: `forgetPeer`, then one retry.
        carol.forgetPeer(daveAddress)
        try processPreKeyBundle(dave2Bundle, for: daveAddress, ourAddress: carolAddress,
                                sessionStore: carol, identityStore: carol, context: ctx)
        let afterReinstall = "and we carry on"
        let framedAfter = try WorldSignalSession.seal(Data(afterReinstall.utf8), to: daveAddress,
                                                      as: carolAddress, store: carol)
        guard try String(data: WorldSignalSession.open(framedAfter, from: carolAddress,
                                                       as: daveAddress, store: dave2),
                         encoding: .utf8) == afterReinstall else {
            throw Failure(step: "session did not re-form after an identity change")
        }
    }
}
#endif
