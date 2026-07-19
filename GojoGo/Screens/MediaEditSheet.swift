import SwiftUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers
import CoreImage
import CoreImage.CIFilterBuiltins
import PhotosUI

// MARK: - PhotosPicker movie transfer

struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("gojogo-\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)")
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Self(url: dest)
        }
    }
}

enum ComposeMediaIngest {
    static func attachments(from items: [PhotosPickerItem],
                            defaultKind: ComposeMediaKind) async -> [ComposeAttachment] {
        var out: [ComposeAttachment] = []
        for item in items {
            if let att = await attachment(from: item, defaultKind: defaultKind) {
                out.append(att)
            }
        }
        return out
    }

    static func attachment(from item: PhotosPickerItem,
                           defaultKind: ComposeMediaKind) async -> ComposeAttachment? {
        let isMovie = item.supportedContentTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) }

        if isMovie {
            if let movie = try? await item.loadTransferable(type: PickedMovie.self) {
                let thumb = await videoThumbnail(url: movie.url) ?? placeholderPoster(for: defaultKind)
                let duration = await videoDurationLabel(url: movie.url)
                let kind: ComposeMediaKind = {
                    switch defaultKind {
                    case .short: return .short
                    case .longForm: return .longForm
                    default: return .photo // photo menu can include videos
                    }
                }()
                return ComposeAttachment(
                    kind: kind,
                    imageData: thumb,
                    durationLabel: duration,
                    videoURL: movie.url
                )
            }
            return ComposeAttachment(
                kind: defaultKind == .textOnly ? .photo : defaultKind,
                imageData: placeholderPoster(for: defaultKind),
                durationLabel: "0:08"
            )
        }

        if let data = try? await item.loadTransferable(type: Data.self),
           UIImage(data: data) != nil {
            let kind: ComposeMediaKind = (defaultKind == .short || defaultKind == .longForm) ? .photo : defaultKind
            return ComposeAttachment(kind: kind == .textOnly ? .photo : kind, imageData: data)
        }

        return nil
    }

    static func videoThumbnail(url: URL) async -> Data? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVURLAsset(url: url)
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = CGSize(width: 720, height: 720)
                let time = CMTime(seconds: 0.1, preferredTimescale: 600)
                if let cg = try? gen.copyCGImage(at: time, actualTime: nil) {
                    let ui = UIImage(cgImage: cg)
                    cont.resume(returning: ui.jpegData(compressionQuality: 0.85))
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    static func videoDurationLabel(url: URL) async -> String {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let secs = max(1, Int(CMTimeGetSeconds(duration).rounded()))
            return String(format: "%d:%02d", secs / 60, secs % 60)
        } catch {
            return "0:08"
        }
    }

    static func placeholderPoster(for kind: ComposeMediaKind) -> Data {
        let icon = kind == .short ? "bolt.fill" : "play.rectangle.fill"
        let size = kind == .short
            ? CGSize(width: 270, height: 480) // 9:16 Reels
            : CGSize(width: 400, height: 225) // 16:9 long-form
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let config = UIImage.SymbolConfiguration(pointSize: 36, weight: .medium)
            if let symbol = UIImage(systemName: icon, withConfiguration: config)?
                .withTintColor(UIColor.white.withAlphaComponent(0.4), renderingMode: .alwaysOriginal) {
                let rect = CGRect(
                    x: (size.width - symbol.size.width) / 2,
                    y: (size.height - symbol.size.height) / 2,
                    width: symbol.size.width,
                    height: symbol.size.height
                )
                symbol.draw(in: rect)
            }
        }
        return image.jpegData(compressionQuality: 0.85) ?? Data()
    }
}

// MARK: - Editor

private enum MediaEditTab: String, CaseIterable, Identifiable {
    case adjust = "Adjust"
    case filter = "Filters"
    case trim = "Trim"
    var id: String { rawValue }
}

private enum MediaFilter: String, CaseIterable, Identifiable {
    case original = "Original"
    case mono = "Mono"
    case contrast = "Punch"
    case soft = "Soft"
    case fade = "Fade"
    var id: String { rawValue }
}

struct MediaEditSheet: View {
    @EnvironmentObject var app: AppState
    let attachmentID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var tab: MediaEditTab = .adjust
    @State private var rotation: Double = 0
    @State private var filter: MediaFilter = .original
    @State private var crop: CropAspect = .original
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 1
    @State private var preview: UIImage?
    @State private var baseImage: UIImage?

    private var attachment: ComposeAttachment? {
        app.composeAttachments.first(where: { $0.id == attachmentID })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GGColor.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    previewPane
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: .infinity)

                    toolTabs
                        .padding(.top, 8)

                    Group {
                        switch tab {
                        case .adjust: adjustTools
                        case .filter: filterTools
                        case .trim: trimTools
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(minHeight: 110)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.8))
                }
                ToolbarItem(placement: .principal) {
                    Text(attachment?.isVideo == true ? "Edit video" : "Edit photo")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { applyAndClose() }
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { load() }
    }

    // MARK: Preview

    private var previewPane: some View {
        ZStack {
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 20)
                    .animation(.easeOut(duration: 0.15), value: preview)
            } else {
                ProgressView().tint(.white)
            }

            if attachment?.isVideo == true {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.35))
                    .allowsHitTesting(false)
            }
        }
    }

    private var toolTabs: some View {
        HStack(spacing: 0) {
            ForEach(availableTabs) { t in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { tab = t }
                } label: {
                    Text(t.rawValue)
                        .font(.system(size: 14, weight: tab == t ? .semibold : .medium))
                        .foregroundStyle(tab == t ? Color.white : Color.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
        }
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
        .padding(.horizontal, 20)
    }

    private var availableTabs: [MediaEditTab] {
        if attachment?.isVideo == true {
            return [.adjust, .filter, .trim]
        }
        return [.adjust, .filter]
    }

    private var adjustTools: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                toolButton(icon: "rotate.left", title: "Rotate") {
                    rotation = (rotation - 90).truncatingRemainder(dividingBy: 360)
                    refreshPreview()
                }
                toolButton(icon: "crop", title: "Square") {
                    crop = crop == .square ? .original : .square
                    refreshPreview()
                }
                toolButton(icon: "rectangle.ratio.16.to.9", title: "Wide") {
                    crop = crop == .wide ? .original : .wide
                    refreshPreview()
                }
                toolButton(icon: "arrow.counterclockwise", title: "Reset") {
                    resetEdits()
                }
            }
            Text(attachment?.isVideo == true
                 ? "Edits apply to the cover. Trim the clip below."
                 : "Rotate, crop, then pick a filter.")
                .font(.system(size: 12))
                .foregroundStyle(GGColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var filterTools: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(MediaFilter.allCases) { f in
                    Button {
                        filter = f
                        refreshPreview()
                    } label: {
                        VStack(spacing: 8) {
                            if let thumb = filtered(baseImage, filter: f, crop: .original, rotation: 0) {
                                Image(uiImage: thumb)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 80)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(filter == f ? Color.white : Color.clear, lineWidth: 2)
                                    )
                            }
                            Text(f.rawValue)
                                .font(.system(size: 11, weight: filter == f ? .semibold : .regular))
                                .foregroundStyle(filter == f ? Color.white : Color.white.opacity(0.45))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var trimTools: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Start")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GGColor.textSecondary)
                Spacer()
                Text(percentLabel(trimStart))
                    .font(.ggMono(12, .medium))
                    .foregroundStyle(.white)
            }
            Slider(value: $trimStart, in: 0...(max(0.01, trimEnd - 0.05)))
                .tint(.white)
                .onChange(of: trimStart) { _, _ in refreshPreview() }

            HStack {
                Text("End")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GGColor.textSecondary)
                Spacer()
                Text(percentLabel(trimEnd))
                    .font(.ggMono(12, .medium))
                    .foregroundStyle(.white)
            }
            Slider(value: $trimEnd, in: (min(0.99, trimStart + 0.05))...1)
                .tint(.white)
                .onChange(of: trimEnd) { _, _ in refreshPreview() }

            Text("Trim length · \(trimLengthLabel)")
                .font(.system(size: 12))
                .foregroundStyle(GGColor.textTertiary)
        }
    }

    private func toolButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: Logic

    private func load() {
        guard let att = attachment else { return }
        let data = att.originalImageData ?? att.imageData
        baseImage = UIImage(data: data)
        trimStart = att.trimStart
        trimEnd = att.trimEnd
        if att.isVideo { tab = .trim }
        refreshPreview()
    }

    private func resetEdits() {
        rotation = 0
        filter = .original
        crop = .original
        trimStart = 0
        trimEnd = 1
        if let att = attachment, let data = att.originalImageData {
            baseImage = UIImage(data: data)
        }
        refreshPreview()
    }

    private func refreshPreview() {
        preview = filtered(baseImage, filter: filter, crop: crop, rotation: rotation)
    }

    private func applyAndClose() {
        guard let image = preview,
              let data = image.jpegData(compressionQuality: 0.9) else {
            dismiss(); return
        }
        app.updateAttachment(attachmentID) { att in
            att.imageData = data
            att.trimStart = trimStart
            att.trimEnd = trimEnd
            if att.isVideo {
                att.durationLabel = trimLengthLabel
            }
        }
        dismiss()
    }

    private func percentLabel(_ v: Double) -> String {
        "\(Int((v * 100).rounded()))%"
    }

    private var trimLengthLabel: String {
        let span = max(0.05, trimEnd - trimStart)
        // Interpret against declared duration if possible
        if let label = attachment?.durationLabel,
           let total = parseDuration(label) {
            let secs = max(1, Int((Double(total) * span).rounded()))
            return String(format: "%d:%02d", secs / 60, secs % 60)
        }
        let secs = max(1, Int((8.0 * span).rounded()))
        return String(format: "0:%02d", secs)
    }

    private func parseDuration(_ label: String) -> Int? {
        let parts = label.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    private func filtered(_ image: UIImage?, filter: MediaFilter, crop: CropAspect, rotation: Double) -> UIImage? {
        guard var ui = image else { return nil }
        ui = cropImage(ui, aspect: crop)
        ui = rotateImage(ui, degrees: rotation)
        guard filter != .original else { return ui }
        guard let ci = CIImage(image: ui) else { return ui }
        let context = CIContext()
        let output: CIImage
        switch filter {
        case .original:
            output = ci
        case .mono:
            let f = CIFilter.photoEffectMono()
            f.inputImage = ci
            output = f.outputImage ?? ci
        case .contrast:
            let f = CIFilter.colorControls()
            f.inputImage = ci
            f.contrast = 1.25
            f.saturation = 1.05
            output = f.outputImage ?? ci
        case .soft:
            let f = CIFilter.colorControls()
            f.inputImage = ci
            f.brightness = 0.05
            f.contrast = 0.92
            f.saturation = 0.85
            output = f.outputImage ?? ci
        case .fade:
            let f = CIFilter.photoEffectFade()
            f.inputImage = ci
            output = f.outputImage ?? ci
        }
        guard let cg = context.createCGImage(output, from: output.extent) else { return ui }
        return UIImage(cgImage: cg, scale: ui.scale, orientation: .up)
    }

    private enum CropAspect { case original, square, wide }

    private func cropImage(_ image: UIImage, aspect: CropAspect) -> UIImage {
        guard aspect != .original, let cg = image.cgImage else { return image }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let target: CGFloat = aspect == .square ? 1 : (16.0 / 9.0)
        let current = w / h
        var rect: CGRect
        if current > target {
            let newW = h * target
            rect = CGRect(x: (w - newW) / 2, y: 0, width: newW, height: h)
        } else {
            let newH = w / target
            rect = CGRect(x: 0, y: (h - newH) / 2, width: w, height: newH)
        }
        guard let cropped = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    private func rotateImage(_ image: UIImage, degrees: Double) -> UIImage {
        let deg = degrees.truncatingRemainder(dividingBy: 360)
        guard abs(deg) > 0.1 else { return image }
        let radians = CGFloat(deg * .pi / 180)
        let newSize = CGRect(origin: .zero, size: image.size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .integral.size
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { ctx in
            ctx.cgContext.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            ctx.cgContext.rotate(by: radians)
            image.draw(in: CGRect(x: -image.size.width / 2,
                                  y: -image.size.height / 2,
                                  width: image.size.width,
                                  height: image.size.height))
        }
    }
}
