import Foundation

// MARK: - Playable file for encrypted attachments (E2EE Phase D)
//
// Images decrypt inside `ImageCache`, which every image surface already goes
// through. Video and audio have no such chokepoint: `AVPlayer` is handed a URL
// and streams it itself, and it has no idea the bytes are ciphertext.
//
// Doing this properly for streaming means an `AVAssetResourceLoaderDelegate`
// that decrypts range requests as they are served. That is real work, and it
// buys nothing here: chat videos and voice notes are short files that are
// fetched whole anyway. So they are downloaded, decrypted once, and written to
// a temp file that the player opens as an ordinary local movie.
//
// The trade is honest and worth stating: playback of a *long* encrypted video
// waits for the whole download instead of starting on the first chunk. If chat
// ever carries long-form video, this is the thing to replace, not the crypto.

enum WorldMediaFile {

    /// Where decrypted attachments live for the life of the process. Under
    /// `tmp/`, so the OS reclaims it and nothing survives to a later launch —
    /// these are plaintext copies of encrypted media and should not linger.
    private static let directory: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gg-media-plain", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// A URL the player can open.
    ///
    /// For anything with no key — every video in the feed, every attachment
    /// sent before Phase D — this hands back the remote URL untouched, so those
    /// keep streaming exactly as they did.
    static func playable(_ remote: URL) async -> URL {
        guard let key = WorldMediaKeyStore.shared.key(for: remote) else { return remote }
        let local = directory.appendingPathComponent(cacheName(for: remote))
        if FileManager.default.fileExists(atPath: local.path) { return local }
        do {
            let (data, _) = try await URLSession.shared.data(from: remote)
            let plain = try WorldMediaCrypto.open(data, key: key)
            try plain.write(to: local, options: .atomic)
            return local
        } catch {
            #if DEBUG
            print("Encrypted media fetch failed (\(remote.lastPathComponent)): \(error)")
            #endif
            // Returning the remote URL lets the player fail its own way rather
            // than silently showing nothing — the bytes are real, they just
            // won't decode, and the player already has a "couldn't load" state.
            return remote
        }
    }

    /// Keeps the remote file's extension: `AVPlayer` sniffs the type from it,
    /// and a decrypted m4a named without one refuses to play.
    private static func cacheName(for url: URL) -> String {
        let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
        var hash: UInt64 = 5381
        for byte in Data(url.absoluteString.utf8) { hash = (hash &* 33) &+ UInt64(byte) }
        return "\(String(hash, radix: 16)).\(ext)"
    }
}
