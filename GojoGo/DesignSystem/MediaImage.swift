import SwiftUI
import UIKit

/// Loads remote, local Data, or falls back to a striped placeholder.
struct MediaImage: View {
    var url: String? = nil
    var data: Data? = nil
    var cornerRadius: CGFloat = 16
    var contentMode: ContentMode = .fill

    var body: some View {
        GeometryReader { geo in
            Group {
                if let data, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else if let url, let u = URL(string: url) {
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
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
            } else if let imageURL, let u = URL(string: imageURL) {
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
