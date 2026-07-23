import CryptoKit
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
    private let io = DispatchQueue(label: "app.gojogo.imagecache", qos: .utility)

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

    /// Full fetch: memory → disk → network. Disk read, network, and decode all run
    /// off the main thread.
    func image(for url: URL) async throws -> UIImage {
        if let hit = memoryImage(for: url) { return hit }
        if let disk = await diskImage(for: url) { return disk }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else { throw CacheError.decodeFailed }
        store(image, data: data, for: url)
        return image
    }

    private func store(_ image: UIImage, data: Data, for url: URL) {
        memory.setObject(image, forKey: url.absoluteString as NSString, cost: data.count)
        let file = fileURL(for: url)
        io.async { try? data.write(to: file, options: .atomic) }
    }

    private func diskImage(for url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            io.async { [weak self] in
                guard let self,
                      let data = try? Data(contentsOf: self.fileURL(for: url)),
                      let image = UIImage(data: data) else {
                    continuation.resume(returning: nil)
                    return
                }
                self.memory.setObject(image, forKey: url.absoluteString as NSString, cost: data.count)
                continuation.resume(returning: image)
            }
        }
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
