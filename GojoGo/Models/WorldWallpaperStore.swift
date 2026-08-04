import UIKit

/// Chat wallpapers the reader picked from their own photos.
///
/// They stay on the device. A wallpaper is a fact about how *you* like to look
/// at a conversation — the other side never sees it, so uploading it would ship
/// somebody's photo to a server for no one's benefit, and the pictures people
/// reach for here are exactly the ones they would not choose to publish.
///
/// Files live in Application Support rather than Caches: the system may empty
/// Caches whenever it likes, and a wallpaper vanishing on a low-storage night
/// would read as the app forgetting a setting.
enum WorldWallpaperStore {

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("WorldWallpapers", isDirectory: true)
    }

    static func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    /// Stores a picked image and returns the file name to keep. Downscaled on
    /// the way in — a modern camera roll image is tens of megabytes, and this is
    /// wallpaper behind a phone screen.
    static func save(_ data: Data) -> String? {
        guard let image = UIImage(data: data),
              let jpeg = downscaled(image).jpegData(compressionQuality: 0.85) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try jpeg.write(to: url(for: name), options: .atomic)
            return name
        } catch {
            #if DEBUG
            print("Wallpaper save failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Decoded wallpapers, kept in memory.
    ///
    /// This is not an optimisation, it is the difference between a usable thread
    /// and an unusable one. `image(named:)` is read from a SwiftUI `body`, and
    /// the chat's body runs on every keystroke, every socket tick and every
    /// republish of AppState — so the un-cached version re-read a multi-megabyte
    /// JPEG off disk and re-decoded it, on the main thread, for every one of
    /// those. Only threads with a photo background were affected, which is
    /// exactly the shape of the lag people reported: the plain ones were fine
    /// and the decorated ones stuttered on everything, typing included.
    private static let decoded: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 8
        return cache
    }()

    static func image(named name: String) -> UIImage? {
        if let hit = decoded.object(forKey: name as NSString) { return hit }
        guard let image = UIImage(contentsOfFile: url(for: name).path) else { return nil }
        // Force the decode here rather than leaving it to the first draw, so the
        // cost lands once instead of on a frame that has a keystroke in it.
        let ready = image.preparingForDisplay() ?? image
        decoded.setObject(ready, forKey: name as NSString)
        return ready
    }

    static func delete(_ name: String) {
        decoded.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: url(for: name))
    }

    /// Longest edge capped at twice the biggest phone dimension, which is past
    /// what any screen can show and well under what a camera produces.
    private static func downscaled(_ image: UIImage, maxEdge: CGFloat = 2400) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
