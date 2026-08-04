import Foundation
import LibSignalClient

// MARK: - Key publishing (E2EE Phase B — see E2EE-PLAN.md)
//
// Puts this device's public bundle in the directory so a sender can start a
// session while we're offline, and keeps the one-time prekey pool topped up.
// Runs on messaging connect; idempotent and cheap when there is nothing to do.
//
// What travels is public material only — the identity *public* key, the signed
// and Kyber prekey publics with their signatures, and one-time publics. The
// private halves are written to `WorldSignalStore` *before* the PUT goes out:
// a bundle the server can hand to a sender whose private half this device
// already lost would poison every session started from it.

// MARK: Wire shapes (mirror KeyDirectoryController's records)

struct WorldSignedPreKeyDTO: Codable {
    var id: Int
    var publicKey: String
    var signature: String
}

struct WorldPreKeyDTO: Codable {
    var id: Int
    var publicKey: String
}

struct WorldPublishKeysBody: Encodable {
    var registrationId: Int
    var identityKey: String
    var signedPreKey: WorldSignedPreKeyDTO
    var kyberPreKey: WorldSignedPreKeyDTO
    var oneTimePreKeys: [WorldPreKeyDTO]
}

struct WorldPreKeyCountDTO: Decodable {
    var oneTimePreKeys: Int
}

struct WorldKeyBundleDTO: Decodable {
    var registrationId: Int
    var deviceId: Int
    var identityKey: String
    var signedPreKey: WorldSignedPreKeyDTO
    var kyberPreKey: WorldSignedPreKeyDTO
    var oneTimePreKey: WorldPreKeyDTO?
}

// MARK: API calls

extension MessagingStore {
    func publishKeys(_ body: WorldPublishKeysBody) async throws {
        try await APIClient.shared.putNoContent("/v1/keys", body: body)
    }

    func preKeyCount() async throws -> Int {
        let dto: WorldPreKeyCountDTO = try await APIClient.shared.get("/v1/keys/count")
        return dto.oneTimePreKeys
    }

    /// A peer's bundle. Consumes one of their one-time prekeys server-side —
    /// call it to *start a session*, never to peek.
    func keyBundle(for profileId: UUID, deviceId: Int = 1) async throws -> WorldKeyBundleDTO {
        try await APIClient.shared.get(
            "/v1/keys/\(profileId.uuidString.lowercased())/\(deviceId)")
    }
}

// MARK: Publisher

enum WorldKeyPublisher {
    /// One-time prekeys minted per publish.
    static let batchSize = 50
    /// Server-side pool level that triggers a top-up.
    static let topUpThreshold = 20

    /// Publishes on first run, tops up when the pool runs low, does nothing
    /// otherwise. Failures are logged and dropped — the next connect retries,
    /// and until the first publish succeeds this account simply can't be
    /// *initiated* to over E2EE, which degrades to exactly today's behaviour.
    static func syncIfNeeded() async {
        do {
            let store = WorldSignalStore.shared
            let published = store.hasPublishedKeys
            let count = published ? try await MessagingStore.shared.preKeyCount() : 0
            guard !published || count < topUpThreshold else { return }

            let (identity, registrationId) = try store.ensureIdentity()
            let signed = try store.currentOrMintSignedPreKey(identity: identity)
            let kyber = try store.currentOrMintKyberPreKey(identity: identity)
            let oneTime = try store.mintOneTimePreKeys(count: batchSize)

            let body = try WorldPublishKeysBody(
                registrationId: Int(registrationId),
                identityKey: identity.publicKey.serialize().base64EncodedString(),
                signedPreKey: WorldSignedPreKeyDTO(
                    id: Int(signed.id),
                    publicKey: signed.publicKey().serialize().base64EncodedString(),
                    signature: signed.signature.base64EncodedString()),
                kyberPreKey: WorldSignedPreKeyDTO(
                    id: Int(kyber.id),
                    publicKey: kyber.publicKey().serialize().base64EncodedString(),
                    signature: kyber.signature.base64EncodedString()),
                oneTimePreKeys: oneTime.map {
                    try WorldPreKeyDTO(
                        id: Int($0.id),
                        publicKey: $0.publicKey().serialize().base64EncodedString())
                })
            try await MessagingStore.shared.publishKeys(body)
            store.markKeysPublished()
            #if DEBUG
            print("E2EE keys published — \(oneTime.count) one-time prekeys banked")
            #endif
        } catch {
            #if DEBUG
            print("Key publish skipped: \(error.localizedDescription)")
            #endif
        }
    }
}

// MARK: Minting (private halves stored before the publics ever leave)

extension WorldSignalStore {
    /// Follows the store's own root — an injected (test) store must not share
    /// the real one's id counter, or prekey ids would collide across them.
    private var metaURL: URL { root.appendingPathComponent("meta.json") }

    private struct PublishMeta: Codable {
        var nextPreKeyId: UInt32 = 1
        var signedPreKeyId: UInt32?
        var kyberPreKeyId: UInt32?
        var published = false
    }

    private func loadMeta() -> PublishMeta {
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(PublishMeta.self, from: data)
        else { return PublishMeta() }
        return meta
    }

    private func saveMeta(_ meta: PublishMeta) {
        guard let data = try? JSONEncoder().encode(meta) else { return }
        try? data.write(to: metaURL,
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    var hasPublishedKeys: Bool { loadMeta().published }

    func markKeysPublished() {
        var meta = loadMeta()
        meta.published = true
        saveMeta(meta)
    }

    /// The signature is the identity key vouching for the prekey — it's what
    /// stops a directory from quietly swapping in its own.
    func currentOrMintSignedPreKey(identity: IdentityKeyPair) throws -> SignedPreKeyRecord {
        var meta = loadMeta()
        if let id = meta.signedPreKeyId,
           let existing = try? loadSignedPreKey(id: id, context: WorldStoreContext()) {
            return existing
        }
        let privateKey = PrivateKey.generate()
        let signature = identity.privateKey.generateSignature(
            message: privateKey.publicKey.serialize())
        let id = meta.nextPreKeyId
        let record = try SignedPreKeyRecord(
            id: id,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            privateKey: privateKey,
            signature: signature)
        try storeSignedPreKey(record, id: id, context: WorldStoreContext())
        meta.signedPreKeyId = id
        meta.nextPreKeyId = id + 1
        saveMeta(meta)
        return record
    }

    func currentOrMintKyberPreKey(identity: IdentityKeyPair) throws -> KyberPreKeyRecord {
        var meta = loadMeta()
        if let id = meta.kyberPreKeyId,
           let existing = try? loadKyberPreKey(id: id, context: WorldStoreContext()) {
            return existing
        }
        let keyPair = KEMKeyPair.generate()
        let signature = identity.privateKey.generateSignature(
            message: keyPair.publicKey.serialize())
        let id = meta.nextPreKeyId
        let record = try KyberPreKeyRecord(
            id: id,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            keyPair: keyPair,
            signature: signature)
        try storeKyberPreKey(record, id: id, context: WorldStoreContext())
        meta.kyberPreKeyId = id
        meta.nextPreKeyId = id + 1
        saveMeta(meta)
        return record
    }

    /// Ids keep counting across batches — a reused id would collide in the
    /// directory's zero-padded sort keys and in this store's files alike.
    func mintOneTimePreKeys(count: Int) throws -> [PreKeyRecord] {
        var meta = loadMeta()
        var records: [PreKeyRecord] = []
        for _ in 0..<count {
            let id = meta.nextPreKeyId
            let record = try PreKeyRecord(id: id, privateKey: PrivateKey.generate())
            try storePreKey(record, id: id, context: WorldStoreContext())
            records.append(record)
            meta.nextPreKeyId = id + 1
        }
        saveMeta(meta)
        return records
    }
}
