import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Sticker library (recents)

/// Recently sent stickers, kept as PNGs in the caches directory. Small and
/// disposable on purpose — losing it costs the user nothing.
@MainActor
final class StickerLibrary: ObservableObject {

    static let shared = StickerLibrary()

    @Published private(set) var recents: [StickerItem] = []

    struct StickerItem: Identifiable, Equatable {
        let id: String
        let data: Data
    }

    private let limit = 18
    private let folder: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("world-stickers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() { load() }

    /// Re-reads the folder — used after the cache is cleared from settings.
    func reload() { load() }

    private func load() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        recents = files
            .sorted { lhs, rhs in modified(lhs) > modified(rhs) }
            .prefix(limit)
            .compactMap { url in
                (try? Data(contentsOf: url)).map { StickerItem(id: url.lastPathComponent, data: $0) }
            }
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    func remember(_ data: Data) {
        let name = "\(UUID().uuidString).png"
        try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
        recents.insert(StickerItem(id: name, data: data), at: 0)
        while recents.count > limit {
            let dropped = recents.removeLast()
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(dropped.id))
        }
    }
}

// MARK: - Sticker sheet

/// iMessage-style sticker drawer. The top half is a live capture field wired to
/// the system emoji/sticker keyboard, so what gets sent is the user's own iOS
/// stickers (Memoji, Live Stickers made from Photos, sticker packs) rather than
/// a stand-in emoji. Recently sent stickers and a quick emoji grid sit below.
struct WorldStickerSheet: View {
    /// A real sticker image (PNG with alpha).
    var onSticker: (Data) -> Void
    /// The emoji fallback row — sends a jumbo-emoji bubble.
    var onEmoji: (String) -> Void
    var onDismiss: () -> Void

    @ObservedObject private var library = StickerLibrary.shared

    private let quickEmoji = ["❤️", "😂", "🔥", "👍", "😮", "😍", "🥳", "😭",
                              "🙏", "👀", "💯", "✨", "😎", "🤝", "🫶", "😅"]

    private let grid = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    captureCard

                    if !library.recents.isEmpty {
                        section("RECENT STICKERS") {
                            LazyVGrid(columns: grid, spacing: 12) {
                                ForEach(library.recents) { item in
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        onSticker(item.data)
                                    } label: {
                                        stickerTile(item.data)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    section("EMOJI") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8),
                                  spacing: 12) {
                            ForEach(quickEmoji, id: \.self) { emoji in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    onEmoji(emoji)
                                } label: {
                                    Text(emoji)
                                        .font(.system(size: 30))
                                        .frame(maxWidth: .infinity)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(IMColor.sheetBG.ignoresSafeArea())
    }

    private var header: some View {
        ZStack {
            Text("Stickers")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(IMColor.label)
            HStack {
                Spacer()
                Button("Done") { onDismiss() }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(IMColor.blue)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    /// The bridge to the OS: a rich text field that accepts sticker insertions,
    /// pastes and drops, and forwards the image straight into the chat.
    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            StickerCaptureField(autoFocus: true) { data in
                StickerLibrary.shared.remember(data)
                onSticker(data)
            }
            .frame(height: 54)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(IMColor.chrome)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(IMColor.blue.opacity(0.35),
                                          style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    )
            )

            HStack(spacing: 6) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 12, weight: .semibold))
                Text("Tap the emoji key, open the Stickers tab, and pick one — it sends straight away. Pasting or dragging a sticker works too.")
                    .font(.system(size: 12))
            }
            .foregroundStyle(IMColor.secondary)
        }
        .padding(.top, 4)
    }

    private func stickerTile(_ data: Data) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(IMColor.chrome.opacity(0.7))
            if let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
            }
        }
        .frame(height: 78)
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IMColor.secondary)
            content()
        }
    }
}

// MARK: - System sticker capture

/// A `UITextView` that exists only to receive stickers from the system keyboard.
///
/// iOS has no API to browse a user's sticker library, but every rich text view
/// can *receive* one: the emoji keyboard's Stickers tab, drag & drop, and paste
/// all insert the sticker as an image (an `NSAdaptiveImageGlyph` on iOS 18+, an
/// `NSTextAttachment` before that). We watch for that insertion, hand the image
/// back, and immediately clear the field so it's ready for the next one.
struct StickerCaptureField: UIViewRepresentable {
    /// Raises the keyboard as the sheet appears, so the sticker tab is one tap away.
    var autoFocus: Bool
    var onSticker: (Data) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSticker: onSticker) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.allowsEditingTextAttributes = true
        view.backgroundColor = .clear
        view.font = .systemFont(ofSize: 17)
        view.textColor = .label
        view.tintColor = .systemBlue
        view.textContainerInset = UIEdgeInsets(top: 14, left: 0, bottom: 14, right: 0)
        view.autocorrectionType = .no
        if #available(iOS 18.0, *) {
            // Lets Genmoji / Live Stickers arrive as adaptive image glyphs.
            view.supportsAdaptiveImageGlyph = true
        }
        context.coordinator.attachPlaceholder(to: view)
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.onSticker = onSticker
        guard autoFocus, !context.coordinator.didFocus, !uiView.isFirstResponder else { return }
        context.coordinator.didFocus = true
        DispatchQueue.main.async { uiView.becomeFirstResponder() }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onSticker: (Data) -> Void
        /// Focus is claimed once — re-claiming on every update fights the user.
        var didFocus = false
        private weak var placeholder: UILabel?

        init(onSticker: @escaping (Data) -> Void) {
            self.onSticker = onSticker
        }

        func attachPlaceholder(to view: UITextView) {
            let label = UILabel()
            label.text = "Drop a sticker here"
            label.font = .systemFont(ofSize: 17)
            label.textColor = .secondaryLabel
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            placeholder = label
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let image = Self.sticker(in: textView.attributedText) else {
                // Sticker-only field: anything typed or pasted as plain text is
                // not a sticker, so drop it rather than leaving junk behind.
                if !textView.attributedText.string.isEmpty {
                    textView.attributedText = NSAttributedString(string: "")
                }
                placeholder?.isHidden = false
                return
            }
            // Consume it: clear the field so the next pick reads cleanly.
            textView.attributedText = NSAttributedString(string: "")
            placeholder?.isHidden = false
            if let data = Self.pngData(from: image) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSticker(data)
            }
        }

        /// Pulls the first sticker image out of an attributed string, covering
        /// both the iOS 18 adaptive-glyph and the classic attachment forms.
        private static func sticker(in attributed: NSAttributedString) -> UIImage? {
            var found: UIImage?
            let full = NSRange(location: 0, length: attributed.length)
            attributed.enumerateAttributes(in: full) { attributes, range, stop in
                if #available(iOS 18.0, *),
                   let glyph = attributes[.adaptiveImageGlyph] as? NSAdaptiveImageGlyph,
                   let image = UIImage(data: glyph.imageContent) {
                    found = image
                    stop.pointee = true
                    return
                }
                guard let attachment = attributes[.attachment] as? NSTextAttachment else { return }
                if let image = attachment.image {
                    found = image
                } else if let data = attachment.fileWrapper?.regularFileContents,
                          let image = UIImage(data: data) {
                    found = image
                } else if let image = attachment.image(forBounds: attachment.bounds,
                                                       textContainer: nil,
                                                       characterIndex: range.location) {
                    found = image
                }
                if found != nil { stop.pointee = true }
            }
            return found
        }

        /// PNG keeps the transparent edges that make a sticker read as a sticker.
        private static func pngData(from image: UIImage) -> Data? {
            let maxDimension: CGFloat = 512
            let longest = max(image.size.width, image.size.height)
            guard longest > maxDimension else { return image.pngData() }
            let scale = maxDimension / longest
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat.default()
            format.opaque = false
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format)
                .pngData { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        }
    }
}
