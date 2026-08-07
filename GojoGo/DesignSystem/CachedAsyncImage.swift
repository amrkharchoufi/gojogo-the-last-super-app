import CryptoKit
import ImageIO
import SwiftUI
import UIKit

/// Two-tier image cache: an in-memory `NSCache` of decoded `UIImage`s (instant,
/// survives view churn) backed by a disk store keyed by a hash of the URL
/// (survives relaunches). This is why remote media stops re-loading every time a
/// cell scrolls back into view — `AsyncImage` keeps neither tier reliably because
/// S3 objects ship without cache-control headers.
final class ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    /// Writes and housekeeping. Serial, and deliberately kept away from reads.
    private let io = DispatchQueue(label: "app.gojogo.imagecache", qos: .utility)
    /// Reads. Concurrent and at a higher priority, because a cache hit is on the
    /// path to a frame. Sharing the serial queue meant every disk hit queued
    /// behind whatever writes were outstanding — and behind the startup prune,
    /// which stats every file in a cache up to 400 MB — so the first screenful
    /// after launch waited on directory housekeeping before it could draw.
    private let reads = DispatchQueue(label: "app.gojogo.imagecache.read",
                                      qos: .userInitiated, attributes: .concurrent)

    /// Longest edge a cached decode is allowed. Past the physical width of the
    /// largest phone screen, so nothing on screen is softer for it — but a
    /// 4000px camera photo costs roughly a quarter of the decode and a quarter
    /// of the memory it used to, which is most of why a feed of them scrolled
    /// badly and evicted itself.
    private static let maxDecodedEdge: CGFloat = 2048

    private init() {
        memory.countLimit = 400
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("gg-image-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        io.async { [weak self] in self?.pruneDisk(maxBytes: 400 * 1024 * 1024) }
    }

    enum CacheError: Error { case decodeFailed }

    /// Synchronous, memory-only lookup — lets a cached image render on first frame
    /// with no spinner flash.
    func memoryImage(for url: URL) -> UIImage? {
        memory.object(forKey: url.absoluteString as NSString)
    }

    /// Whether this URL is already cached on either tier — a `stat`, not a read,
    /// so it is cheap enough to ask from `body`. Callers use it to decide whether
    /// a placeholder is worth drawing at all: a disk hit resolves within a frame
    /// or two, and flashing an initial in front of it reads as a glitch.
    func isCached(_ url: URL) -> Bool {
        if memoryImage(for: url) != nil { return true }
        return FileManager.default.fileExists(atPath: fileURL(for: url).path)
    }

    /// Full fetch: memory → disk → network. Disk read, network, and decode all run
    /// off the main thread.
    func image(for url: URL) async throws -> UIImage {
        if let hit = memoryImage(for: url) { return hit }
        if let disk = await diskImage(for: url) { return disk }

        let (raw, _) = try await URLSession.shared.data(from: url)
        // E2EE Phase D: chat attachments arrive as ciphertext. The key is looked
        // up by URL, so this is the one place that has to know — every caller
        // (`MediaImage`, feed cells, avatars, the viewer) is untouched, and a
        // URL with no key is used exactly as before, which is what keeps
        // non-chat images and pre-Phase-D attachments rendering.
        let data = try Self.decrypted(raw, for: url)
        guard let image = Self.decode(data) else { throw CacheError.decodeFailed }
        // Plaintext on both tiers, deliberately: caching ciphertext would mean
        // decrypting on every scroll tick, and the disk cache already holds
        // decoded photos from every other surface in the app.
        store(image, data: data, for: url)
        return image
    }

    /// Decrypts a chat attachment; returns the bytes untouched when there is no
    /// key for this URL.
    static func decrypted(_ data: Data, for url: URL) throws -> Data {
        guard let key = WorldMediaKeyStore.shared.key(for: url) else { return data }
        return try WorldMediaCrypto.open(data, key: key)
    }

    private func store(_ image: UIImage, data: Data, for url: URL) {
        memory.setObject(image, forKey: url.absoluteString as NSString, cost: data.count)
        let file = fileURL(for: url)
        io.async { try? data.write(to: file, options: .atomic) }
    }

    private func diskImage(for url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            reads.async { [weak self] in
                guard let self,
                      let data = try? Data(contentsOf: self.fileURL(for: url),
                                           options: .mappedIfSafe),
                      let image = Self.decode(data) else {
                    continuation.resume(returning: nil)
                    return
                }
                self.memory.setObject(image, forKey: url.absoluteString as NSString, cost: data.count)
                continuation.resume(returning: image)
            }
        }
    }

    /// Decodes at display scale rather than at the camera's.
    ///
    /// Two things matter here and `UIImage(data:)` does neither. It decodes at
    /// full source resolution — a 4032×3024 photo becomes ~48 MB of bitmap for a
    /// cell a few hundred points wide, which is what pushes everything else out
    /// of the memory cache and makes scrolling back re-fetch. And it decodes
    /// *lazily*, on the main thread, at the moment the image is first drawn —
    /// so the work lands inside a frame instead of on this background queue.
    /// ImageIO's thumbnail path solves both, and never upscales, so a small
    /// image (an avatar) comes back untouched.
    private static func decode(_ data: Data) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDecodedEdge,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            // Anything ImageIO won't open (an animated or exotic format) still
            // gets the old path rather than nothing.
            return UIImage(data: data)
        }
        return UIImage(cgImage: thumb)
    }

    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }

    /// Keeps the on-disk cache bounded by evicting the least-recently-modified files.
    private func pruneDisk(maxBytes: Int) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys) else { return }

        let entries = files.compactMap { url -> (url: URL, size: Int, date: Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > maxBytes else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
            if total <= maxBytes { break }
        }
    }
}

// MARK: - Prefetch

/// Warms `ImageCache` for images the user is *about* to see, so a feed cell has
/// its photo decoded before it scrolls on screen — the reason posts feel
/// "already there" instead of flashing a spinner. Bounded concurrency (so a
/// burst of look-ahead requests can't starve the visible cell's own load),
/// in-flight de-duplication, and a free skip for anything already in memory.
actor ImagePrefetcher {
    static let shared = ImagePrefetcher()

    private var inFlight: Set<String> = []
    private var pending: [URL] = []
    private var active = 0
    private let maxConcurrent = 4

    /// Queue a look-ahead warm for these URLs. Already-cached or already-queued
    /// URLs are dropped; the rest fetch newest-request-first-ish via a small pool.
    func prefetch(_ urls: [URL]) {
        for url in urls {
            let key = url.absoluteString
            if inFlight.contains(key) { continue }
            if ImageCache.shared.memoryImage(for: url) != nil { continue }
            inFlight.insert(key)
            pending.append(url)
        }
        pump()
    }

    private func pump() {
        while active < maxConcurrent, !pending.isEmpty {
            let url = pending.removeFirst()
            active += 1
            Task { await self.run(url) }
        }
    }

    private func run(_ url: URL) async {
        _ = try? await ImageCache.shared.image(for: url)
        active -= 1
        inFlight.remove(url.absoluteString)
        pump()
    }
}

// MARK: - View

enum CachedImagePhase {
    case loading
    case success(Image)
    case failure
}

/// Drop-in, cached replacement for `AsyncImage(url:)` with a phase-style API.
/// A memory-cache hit renders synchronously on the first frame (no flash).
struct CachedAsyncImage<Content: View>: View {
    let url: URL
    @ViewBuilder var content: (CachedImagePhase) -> Content

    @State private var phase: CachedImagePhase

    init(url: URL, @ViewBuilder content: @escaping (CachedImagePhase) -> Content) {
        self.url = url
        self.content = content
        // Seed from the memory cache so already-loaded images never show a spinner.
        if let cached = ImageCache.shared.memoryImage(for: url) {
            _phase = State(initialValue: .success(Image(uiImage: cached)))
        } else {
            _phase = State(initialValue: .loading)
        }
    }

    var body: some View {
        content(phase)
            .task(id: url) { await load() }
    }

    private func load() async {
        if let cached = ImageCache.shared.memoryImage(for: url) {
            phase = .success(Image(uiImage: cached))
            return
        }
        phase = .loading
        do {
            let image = try await ImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            phase = .success(Image(uiImage: image))
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failure
        }
    }
}
