import SwiftUI
import AVFoundation
import PhotosUI
import UIKit

/// Title, description and cover for a long-form video.
///
/// Two entry points, one form: `.attachment` edits a compose attachment before
/// it is published, `.published` edits a video that already exists. The cover
/// is either a frame lifted off the actual movie or a picture from the library —
/// there is no generated placeholder here, so what you set is what viewers see.
enum VideoDetailsTarget: Equatable {
    case attachment(UUID)
    case published(UUID)
}

struct VideoDetailsSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let target: VideoDetailsTarget

    @State private var title = ""
    @State private var details = ""
    @State private var cover: UIImage?
    @State private var coverChanged = false
    @State private var frames: [UIImage] = []
    @State private var loadingFrames = true
    @State private var pickerItem: PhotosPickerItem?
    @State private var loaded = false

    private var isPublished: Bool {
        if case .published = target { return true }
        return false
    }

    private var attachment: ComposeAttachment? {
        guard case .attachment(let id) = target else { return nil }
        return app.composeAttachments.first(where: { $0.id == id })
    }

    private var video: VideoItem? {
        guard case .published(let id) = target else { return nil }
        return app.videos.first(where: { $0.id == id })
    }

    /// Playable URL for the movie behind either target.
    private var sourceURL: URL? {
        if let att = attachment { return att.videoURL }
        guard let raw = video?.videoURL,
              let resolved = VideoLibrary.resolve(raw) else { return nil }
        return URL(string: resolved)
    }

    private var durationLabel: String {
        attachment?.durationLabel ?? video?.duration ?? "—"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GGColor.sheetBG.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        coverSection
                        titleField
                        descriptionField
                        factsRow
                    }
                    .padding(20)
                }
            }
            .navigationTitle(isPublished ? "Edit video" : "Video details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { close() }
                        .foregroundStyle(GGColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isPublished ? "Save" : "Done") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(GGColor.accent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(GGColor.sheetBG)
        .onAppear(perform: load)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    await MainActor.run {
                        cover = ui
                        coverChanged = true
                    }
                }
            }
        }
    }

    // MARK: Cover

    private var coverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Thumbnail")

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(GGColor.ink(0.10))
                if let cover {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 22))
                        Text("No cover yet")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(GGColor.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if loadingFrames {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading frames from the clip…")
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textTertiary)
                }
            } else if !frames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                cover = frame
                                coverChanged = true
                            } label: {
                                Image(uiImage: frame)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 84, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(cover === frame ? GGColor.accent : Color.clear,
                                                          lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choose from library", systemImage: "photo.on.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.accent)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .glassCapsule()
            }
        }
    }

    // MARK: Fields

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Title")
            TextField("Add a title", text: $title, axis: .vertical)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .lineLimit(1...3)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(GGColor.ink(0.08)))
            Text("\(title.count)/100")
                .font(.ggMono(11, .regular))
                .foregroundStyle(title.count > 100 ? GGColor.red : GGColor.textTertiary)
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Description")
            TextField("Tell viewers about this video", text: $details, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(GGColor.textPrimary)
                .lineLimit(4...12)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(GGColor.ink(0.08)))
        }
    }

    private var factsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Details")
            fact("Length", durationLabel)
            fact("Channel", "@\(app.user.handle)")
            if let video {
                fact("Views", video.views == 1 ? "1 view" : "\(formatCount(video.views)) views")
                fact("Published", RelativeTime.since(video.publishedAt))
            } else {
                fact("Publishes to", "Watch — long-form feed")
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GGColor.textSecondary)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(GGColor.textSecondary)
    }

    // MARK: Logic

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let att = attachment {
            title = att.title
            details = att.details
            cover = UIImage(data: att.imageData)
        } else if let video {
            title = video.title
            details = video.details
            if let data = video.thumbData { cover = UIImage(data: data) }
        }
        loadFrames()
    }

    /// Six evenly spaced stills so a cover can come from the clip itself.
    private func loadFrames() {
        guard let url = sourceURL else {
            loadingFrames = false
            return
        }
        Task {
            let asset = AVURLAsset(url: url)
            guard let total = try? await asset.load(.duration),
                  CMTimeGetSeconds(total).isFinite,
                  CMTimeGetSeconds(total) > 0 else {
                await MainActor.run { loadingFrames = false }
                return
            }
            let seconds = CMTimeGetSeconds(total)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 480)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

            var picked: [UIImage] = []
            for step in 0..<6 {
                let at = seconds * (Double(step) + 0.5) / 6
                let time = CMTime(seconds: at, preferredTimescale: 600)
                if let cg = try? await generator.image(at: time).image {
                    picked.append(UIImage(cgImage: cg))
                }
            }
            let result = picked
            await MainActor.run {
                frames = result
                loadingFrames = false
                if cover == nil { cover = result.first }
            }
        }
    }

    private func save() {
        let coverData = coverChanged ? cover?.jpegData(compressionQuality: 0.9) : nil
        switch target {
        case .attachment(let id):
            app.updateAttachment(id) { att in
                att.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                att.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
                if let coverData { att.imageData = coverData }
            }
        case .published(let id):
            app.updateVideoDetails(id, title: title, details: details, thumbData: coverData)
        }
        close()
    }

    private func close() {
        app.closeVideoDetails()
        dismiss()
    }
}
