import SwiftUI
import UIKit

/// Loads bundled asset names, remote URLs, local Data, or a striped placeholder.
///
/// Uses a clear sized container + overlay (not GeometryReader) so the hit target
/// matches the visible frame. GeometryReader was expanding taps past clipped bounds
/// and stealing touches from nearby controls (profile tabs, category chips, etc.).
struct MediaImage: View {
    var url: String? = nil
    var data: Data? = nil
    var cornerRadius: CGFloat = 16
    var contentMode: ContentMode = .fill

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        Color.clear
            .overlay {
                media
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipped()
            .clipShape(shape)
            .contentShape(shape)
    }

    @ViewBuilder
    private var media: some View {
        if let data, let ui = Self.decoded(data) {
            Image(uiImage: ui)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else if let url, let ui = Self.bundledImage(named: url) {
            Image(uiImage: ui)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else if let url, let u = URL(string: url), u.scheme != nil {
            CachedAsyncImage(url: u) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: contentMode)
                case .failure:
                    MediaPlaceholder(cornerRadius: 0)
                case .loading:
                    ZStack {
                        GGColor.surface2
                        ProgressView().tint(GGColor.textTertiary)
                    }
                }
            }
        } else {
            MediaPlaceholder(cornerRadius: 0)
        }
    }

    /// Decoded-image cache keyed by the bytes' identity.
    ///
    /// `body` runs on every render pass, so decoding inline meant re-decoding
    /// every inline photo on each scroll tick — very visible in a chat thread.
    private static let decodedCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        return cache
    }()

    static func decoded(_ data: Data) -> UIImage? {
        let key = "\(data.count)-\(data.hashValue)" as NSString
        if let cached = decodedCache.object(forKey: key) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        decodedCache.setObject(image, forKey: key)
        return image
    }

    /// Asset catalog name, or `asset:Name` / `asset://Name` from older session strings.
    static func bundledImage(named raw: String) -> UIImage? {
        let name: String
        if raw.hasPrefix("asset://") {
            name = String(raw.dropFirst("asset://".count))
        } else if raw.hasPrefix("asset:") {
            name = String(raw.dropFirst("asset:".count))
        } else if raw.contains("://") || raw.hasPrefix("http") {
            return nil
        } else {
            name = raw
        }
        guard !name.isEmpty else { return nil }
        return UIImage(named: name)
    }
}

/// Photo-backed avatar; falls back to letter / solid disc.
struct UserAvatar: View {
    var size: CGFloat = 32
    var gradient: [Color] = []
    var letter: String? = nil
    var ring: Bool = false
    var imageURL: String? = nil
    var imageData: Data? = nil

    var body: some View {
        Group {
            if ring {
                Circle()
                    .fill(GGColor.blue)
                    .padding(-2)
                    .overlay(inner)
                    .frame(width: size, height: size)
            } else {
                inner.frame(width: size, height: size)
            }
        }
    }

    /// An empty letter is "no initial known yet" (a ring seeded before the
    /// profile loaded), which should draw a plain disc rather than blank `Text`.
    private var displayLetter: String? {
        guard let letter, !letter.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return letter
    }

    @ViewBuilder
    private var letterView: some View {
        if let displayLetter {
            Text(displayLetter)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
        }
    }

    private var inner: some View {
        ZStack {
            Circle().fill(GGColor.surface2)
            // Same decoded-bytes cache as MediaImage — `body` runs per render
            // pass, and avatars sit in every list row.
            if let imageData, let ui = MediaImage.decoded(imageData) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else if let imageURL, let ui = MediaImage.bundledImage(named: imageURL) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else if let imageURL, let u = URL(string: imageURL), u.scheme != nil {
                CachedAsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .loading:
                        // An already-cached photo is a frame or two away, so the
                        // initial would only flash in front of it — that swap is
                        // what reads as a glitch on the feed's own avatar right
                        // after signing in. Uncached, the letter earns its place.
                        if !ImageCache.shared.isCached(u) { letterView }
                    case .failure:
                        letterView
                    }
                }
            } else {
                letterView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(ring ? Circle().strokeBorder(GGColor.bg, lineWidth: 3) : nil)
    }
}
