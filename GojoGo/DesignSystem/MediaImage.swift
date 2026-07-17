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
        if let data, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else if let url, let ui = Self.bundledImage(named: url) {
            Image(uiImage: ui)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else if let url, let u = URL(string: url), u.scheme != nil {
            AsyncImage(url: u) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: contentMode)
                case .failure:
                    MediaPlaceholder(cornerRadius: 0)
                case .empty:
                    ZStack {
                        GGColor.surface2
                        ProgressView().tint(GGColor.textTertiary)
                    }
                @unknown default:
                    MediaPlaceholder(cornerRadius: 0)
                }
            }
        } else {
            MediaPlaceholder(cornerRadius: 0)
        }
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

    private var inner: some View {
        ZStack {
            Circle().fill(GGColor.surface2)
            if let imageData, let ui = UIImage(data: imageData) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else if let imageURL, let ui = MediaImage.bundledImage(named: imageURL) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else if let imageURL, let u = URL(string: imageURL), u.scheme != nil {
                AsyncImage(url: u) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else if let letter {
                        Text(letter)
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                    }
                }
            } else if let letter {
                Text(letter)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(ring ? Circle().strokeBorder(GGColor.bg, lineWidth: 3) : nil)
    }
}
