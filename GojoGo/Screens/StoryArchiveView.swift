import SwiftUI

/// Your story archive — every frame you've posted, expiry ignored — and the
/// highlights you build out of it.
///
/// The archive is the only place an expired story still exists, so it is also
/// the only sensible place to build a highlight from.
struct StoryArchiveView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var buildingHighlight = false
    @State private var loading = true

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        NavigationStack {
            ZStack {
                GGColor.bg.ignoresSafeArea()

                if loading && app.storyArchive.isEmpty {
                    ProgressView().tint(GGColor.textSecondary)
                } else if app.storyArchive.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $buildingHighlight) {
            StoryHighlightEditor(frameIDs: Array(selection)) {
                selecting = false
                selection = []
            }
            .environmentObject(app)
        }
        .task {
            await app.refreshStoryArchive()
            await app.refreshHighlights()
            loading = false
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(selecting ? "Cancel" : "Select") {
                withAnimation(.ggSnappy) {
                    selecting.toggle()
                    selection = []
                }
            }
            .foregroundStyle(GGColor.accent)
            .opacity(app.storyArchive.isEmpty ? 0 : 1)
        }
        ToolbarItem(placement: .topBarTrailing) {
            if selecting {
                Button("New highlight") { buildingHighlight = true }
                    .fontWeight(.semibold)
                    .foregroundStyle(GGColor.accent)
                    .disabled(selection.isEmpty)
            } else {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
                    .foregroundStyle(GGColor.accent)
            }
        }
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if !app.storyHighlights.isEmpty {
                    highlightsStrip
                }

                Text(selecting ? "Pick the frames for your highlight" : "Your stories")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GGColor.textSecondary)
                    .padding(.horizontal, 16)

                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(app.storyArchive) { frame in
                        cell(frame)
                    }
                }
                .padding(.horizontal, 3)
                .padding(.bottom, 30)
            }
            .padding(.top, 10)
        }
    }

    private var highlightsStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Highlights")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GGColor.textSecondary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(app.storyHighlights) { highlight in
                        StoryHighlightBubble(highlight: highlight, size: 66)
                            .onTapGesture {
                                dismiss()
                                app.openHighlight(highlight)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    app.deleteHighlight(highlight.id)
                                } label: {
                                    Label("Delete highlight", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func cell(_ frame: StoryFrame) -> some View {
        let isSelected = selection.contains(frame.id)
        return ZStack(alignment: .topTrailing) {
            StoryThumbnail(frame: frame)
                .aspectRatio(9 / 16, contentMode: .fill)
                .clipped()

            if selecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? GGColor.accent : .white.opacity(0.85))
                    .padding(6)
                    .shadow(color: .black.opacity(0.4), radius: 4)
            }
        }
        .overlay {
            if selecting && isSelected {
                Rectangle().fill(Color.black.opacity(0.3))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard selecting else { return }
            if isSelected { selection.remove(frame.id) } else { selection.insert(frame.id) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(GGColor.textTertiary)
            Text("Nothing archived yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
            Text("Stories you post are kept here after they expire, so you can turn them into highlights.")
                .explanatory(13)
                .foregroundStyle(GGColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Shared bits

/// A frame at thumbnail size — a text card renders as its card, not a blank.
struct StoryThumbnail: View {
    let frame: StoryFrame

    var body: some View {
        ZStack {
            switch frame.kind {
            case .text:
                ZStack {
                    frame.background.gradient
                    Text(frame.caption ?? "")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(frame.background.foreground)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(4)
                }
            case .image, .video:
                MediaImage(url: frame.imageURL, data: frame.imageData, cornerRadius: 0)
            }

            if frame.kind == .video {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(6)
            }
            if frame.audience == .closeFriends {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(6)
            }
        }
        .background(GGColor.surface)
    }
}

/// The circular highlight cover used on the profile and in the archive.
struct StoryHighlightBubble: View {
    let highlight: StoryHighlight
    var size: CGFloat = 62

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(GGColor.surface)
                if let cover = highlight.coverURL {
                    MediaImage(url: cover, cornerRadius: size / 2)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: size * 0.32))
                        .foregroundStyle(GGColor.textTertiary)
                }
            }
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(GGColor.hairline, lineWidth: 1))

            Text(highlight.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(GGColor.textSecondary)
                .lineLimit(1)
                .frame(width: size + 10)
        }
    }
}

// MARK: - Building a highlight

/// Names a new highlight (or renames one) over a chosen set of frames.
struct StoryHighlightEditor: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var existing: StoryHighlight? = nil
    let frameIDs: [UUID]
    var onSaved: () -> Void = {}

    @State private var title = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ZStack {
                GGColor.sheetBG.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    Text("Highlights stay on your profile after a story expires.")
                        .explanatory(13)
                        .foregroundStyle(GGColor.textSecondary)

                    TextField("Highlight name", text: $title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(GGColor.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(GGColor.surface))

                    Text("\(frameIDs.count) \(frameIDs.count == 1 ? "story" : "stories") selected")
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textTertiary)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle(existing == nil ? "New highlight" : "Edit highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(GGColor.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(saving ? "Saving…" : "Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(GGColor.accent)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.medium])
        .onAppear { title = existing?.title ?? "" }
    }

    private func save() {
        saving = true
        Task {
            let ok = await app.saveHighlight(
                id: existing?.id, title: title, coverURL: nil, frameIDs: frameIDs)
            saving = false
            if ok {
                onSaved()
                dismiss()
            }
        }
    }
}

/// Adds the frame you're looking at to an existing highlight, or starts a new one.
struct StoryHighlightPickerSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let frameIDs: [UUID]
    @State private var creating = false

    var body: some View {
        NavigationStack {
            ZStack {
                GGColor.sheetBG.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Button {
                            creating = true
                        } label: {
                            row(icon: "plus", title: "New highlight", subtitle: nil)
                        }
                        Divider().overlay(GGColor.hairline).padding(.leading, 62)

                        ForEach(app.storyHighlights) { highlight in
                            Button {
                                add(to: highlight)
                            } label: {
                                row(icon: "bookmark.fill",
                                    title: highlight.title,
                                    subtitle: "\(highlight.frameCount) \(highlight.frameCount == 1 ? "story" : "stories")")
                            }
                            Divider().overlay(GGColor.hairline).padding(.leading, 62)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .navigationTitle("Add to highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(GGColor.accent)
                }
            }
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.medium])
        .sheet(isPresented: $creating) {
            StoryHighlightEditor(frameIDs: frameIDs) { dismiss() }
                .environmentObject(app)
        }
        .task { await app.refreshHighlights() }
    }

    private func row(icon: String, title: String, subtitle: String?) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(GGColor.surface).frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(GGColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textTertiary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    /// Appending means re-sending the whole set — the API replaces a highlight's
    /// frames wholesale, so the existing ones have to come along.
    private func add(to highlight: StoryHighlight) {
        Task {
            guard let current = try? await StoriesStore.shared.highlightFrames(highlight.id) else {
                app.showStoryNotice("Couldn't open that highlight.")
                return
            }
            var ids = current.frames.map(\.id)
            for id in frameIDs where !ids.contains(id) {
                ids.append(id)
            }
            if await app.saveHighlight(id: highlight.id, title: highlight.title,
                                       coverURL: highlight.coverURL, frameIDs: ids) {
                app.showStoryNotice("Added to \(highlight.title)")
                dismiss()
            }
        }
    }
}
