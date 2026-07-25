import SwiftUI
import PhotosUI
import UIKit

/// Full-screen story composer: pick or shoot media (or write a text card), drop
/// text and stickers on it, choose who sees it, post.
///
/// Overlays are placed by direct manipulation and stored as a normalized spec,
/// never burned into the image — see `StoryOverlay`. What you see here is
/// rendered by the exact same `StoryFrameCanvas` the viewer uses, so the
/// composer preview is the story, not an approximation of it.
struct StoryComposer: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var draft = DraftStoryFrame(kind: .text, caption: nil)
    @State private var overlays: [StoryOverlay] = []
    @State private var selectedOverlay: UUID?
    @State private var picker: PhotosPickerItem?
    @State private var showPicker = false
    @State private var showCamera = false
    @State private var showStickers = false
    @State private var showMusic = false
    @State private var editingText: StoryOverlay?
    @State private var textDraft = ""
    @State private var captionFocused = false
    @State private var posting = false

    @FocusState private var captionFieldFocused: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                canvas(size: geo.size)

                if draft.kind == .text && !captionFieldFocused && (draft.caption ?? "").isEmpty {
                    Text("Tap to type")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(draft.background.foreground.opacity(0.5))
                        .allowsHitTesting(false)
                }

                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    bottomBar
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .preferredColorScheme(.dark)
        .photosPicker(isPresented: $showPicker, selection: $picker, matching: .any(of: [.images, .videos]))
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView(
                onCapture: { capture in
                    showCamera = false
                    apply(capture)
                },
                onCancel: { showCamera = false })
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showStickers) {
            WorldStickerSheet(
                onSticker: { data in
                    addSticker(data)
                    showStickers = false
                },
                // The emoji row doubles as a big emoji sticker on a story.
                onEmoji: { emoji in
                    addEmoji(emoji)
                    showStickers = false
                },
                onDismiss: { showStickers = false })
        }
        .sheet(isPresented: $showMusic) {
            MusicPickerSheet(current: draft.music) { picked in
                withAnimation(.ggSnappy) { draft.music = picked }
            }
            .environmentObject(app)
        }
        .sheet(item: $editingText) { overlay in
            StoryTextEditorSheet(
                text: overlay.text ?? "",
                isLight: overlay.isLight,
                onSave: { text, isLight in
                    updateText(overlay.id, text: text, isLight: isLight)
                    editingText = nil
                },
                onDelete: {
                    overlays.removeAll { $0.id == overlay.id }
                    editingText = nil
                })
        }
        .onChange(of: picker) { _, item in
            guard let item else { return }
            Task {
                await ingest(item)
                picker = nil
            }
        }
    }

    // MARK: Canvas

    private func canvas(size: CGSize) -> some View {
        ZStack {
            // The sticker is drawn by the bar below instead, so it sits clear of
            // the tool row and can be tapped to change the track.
            StoryFrameCanvas(frame: previewFrame, isActive: true, isMuted: false,
                             showsMusicSticker: false)
                .ignoresSafeArea()

            // Overlays are interactive here (the canvas draws them inert), so
            // they're re-drawn on top with gestures attached.
            ForEach($overlays) { $overlay in
                StoryOverlayHandle(
                    overlay: $overlay,
                    canvas: size,
                    isSelected: selectedOverlay == overlay.id,
                    onSelect: { selectedOverlay = overlay.id },
                    onEdit: { if overlay.kind == .text { editingText = overlay } },
                    onDelete: { overlays.removeAll { $0.id == overlay.id } })
            }

            if draft.kind == .text {
                TextField("", text: Binding(
                    get: { draft.caption ?? "" },
                    set: { draft.caption = $0 }),
                    axis: .vertical)
                    .focused($captionFieldFocused)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.clear)          // the canvas draws the real text
                    .tint(draft.background.foreground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, size.width * 0.12)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if draft.kind == .text {
                captionFieldFocused = true
            }
            selectedOverlay = nil
        }
    }

    /// The draft as the viewer would play it — the composer previews the real thing.
    private var previewFrame: StoryFrame {
        StoryFrame(
            kind: draft.kind,
            imageData: draft.imageData,
            localVideoURL: draft.videoFileURL,
            durationMs: draft.durationMs,
            caption: draft.caption,
            background: draft.background,
            overlays: [],                 // drawn separately so they stay draggable
            audience: draft.audience,
            music: draft.music)
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .glassCapsule(interactive: true)
            }

            Spacer()

            toolButton("textformat", label: "Text") { addText() }
            toolButton("face.smiling", label: "Sticker") { showStickers = true }
            toolButton(draft.music == nil ? "music.note" : "music.note.list",
                       label: "Music", highlighted: draft.music != nil) {
                showMusic = true
            }
            if draft.kind == .text {
                toolButton("circle.righthalf.filled", label: "Background") { cycleBackground() }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if let music = draft.music {
                Button { showMusic = true } label: {
                    HStack(spacing: 8) {
                        StoryMusicSticker(music: music, isPlaying: false)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if draft.kind == .text {
                backgroundStrip
            }

            HStack(spacing: 10) {
                sourceButton("photo.on.rectangle", "Gallery") { showPicker = true }
                // No camera in the Simulator — fall back rather than presenting
                // an empty picker.
                sourceButton("camera.fill", "Camera") {
                    if CameraCaptureView.isAvailable { showCamera = true } else { showPicker = true }
                }
                sourceButton("textformat.alt", "Text") { switchToText() }

                Spacer(minLength: 0)
            }

            // The audience pill shares the row with Share: four pills across
            // 402pt wrapped their labels, and this reads better anyway — you
            // pick who sees it right where you send it.
            HStack(spacing: 10) {
                audienceButton

                Button {
                    post()
                } label: {
                    HStack(spacing: 8) {
                        if posting {
                            ProgressView().tint(GGColor.onAccent)
                        }
                        Text(posting ? "Sharing…" : "Share")
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(GGColor.onAccent)
                    .background(Capsule().fill(canPost ? GGColor.accent : GGColor.accent.opacity(0.35)))
                }
                .disabled(!canPost || posting)
            }
        }
    }

    private var backgroundStrip: some View {
        HStack(spacing: 10) {
            ForEach(StoryBackground.allCases, id: \.self) { option in
                Circle()
                    .fill(option.gradient)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle().strokeBorder(
                            draft.background == option ? Color.white : Color.white.opacity(0.25),
                            lineWidth: draft.background == option ? 2 : 0.5))
                    .onTapGesture {
                        withAnimation(.ggSnappy) { draft.background = option }
                    }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .glassCapsule()
    }

    private var audienceButton: some View {
        Button {
            withAnimation(.ggSnappy) {
                draft.audience = draft.audience == .everyone ? .closeFriends : .everyone
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: draft.audience.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(draft.audience.label)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .glassCapsule(interactive: true)
        }
    }

    private func toolButton(_ icon: String, label: String, highlighted: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(highlighted ? GGColor.onAccent : .white)
                .frame(width: 38, height: 38)
                .background {
                    if highlighted { Circle().fill(GGColor.accent) }
                }
                .glassCapsule(interactive: true)
        }
        .accessibilityLabel(label)
    }

    private func sourceButton(_ icon: String, _ title: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
            }
            .fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassCapsule(interactive: true)
        }
    }

    // MARK: Actions

    private var canPost: Bool {
        switch draft.kind {
        case .text: (draft.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .image: draft.imageData != nil
        case .video: draft.videoFileURL != nil
        }
    }

    private func switchToText() {
        withAnimation(.ggSnappy) {
            draft.kind = .text
            draft.imageData = nil
            draft.videoFileURL = nil
            draft.durationMs = nil
        }
        captionFieldFocused = true
    }

    private func cycleBackground() {
        let all = StoryBackground.allCases
        let next = (all.firstIndex(of: draft.background).map { $0 + 1 } ?? 0) % all.count
        withAnimation(.ggSnappy) { draft.background = all[next] }
    }

    private func addText() {
        let overlay = StoryOverlay(kind: .text, text: "", y: 0.4)
        overlays.append(overlay)
        editingText = overlay
    }

    private func updateText(_ id: UUID, text: String, isLight: Bool) {
        guard let i = overlays.firstIndex(where: { $0.id == id }) else { return }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            overlays.remove(at: i)
            return
        }
        overlays[i].text = cleaned
        overlays[i].isLight = isLight
    }

    private func addSticker(_ data: Data) {
        overlays.append(StoryOverlay(kind: .sticker, imageData: data, y: 0.5, fontScale: 0.32))
    }

    /// A jumbo emoji is just a text overlay that starts big.
    private func addEmoji(_ emoji: String) {
        overlays.append(StoryOverlay(kind: .text, text: emoji, y: 0.5, fontScale: 0.22))
    }

    private func apply(_ capture: CameraCaptureView.Capture) {
        switch capture {
        case .photo(let data):
            draft.kind = .image
            draft.imageData = data
            draft.videoFileURL = nil
            draft.durationMs = nil
        case .video(let poster, let durationLabel, let url):
            draft.kind = .video
            draft.imageData = poster
            draft.videoFileURL = url
            draft.durationMs = Self.milliseconds(from: durationLabel)
        }
    }

    private func ingest(_ item: PhotosPickerItem) async {
        guard let attachment = await ComposeMediaIngest.attachment(from: item, defaultKind: .photo)
        else { return }
        if let movie = attachment.videoURL {
            draft.kind = .video
            draft.imageData = attachment.imageData
            draft.videoFileURL = movie
            draft.durationMs = Self.milliseconds(from: attachment.durationLabel)
        } else {
            draft.kind = .image
            draft.imageData = attachment.imageData
            draft.videoFileURL = nil
            draft.durationMs = nil
        }
    }

    private func post() {
        guard canPost, !posting else { return }
        posting = true
        var outgoing = draft
        outgoing.overlays = overlays
        if outgoing.kind != .text { outgoing.caption = nil }
        app.postStory([outgoing])
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    /// "1:23" → 83000. The pickers hand back a label, not a duration.
    static func milliseconds(from label: String?) -> Int? {
        guard let label else { return nil }
        let parts = label.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        let seconds = parts.reduce(0) { $0 * 60 + $1 }
        return seconds > 0 ? seconds * 1000 : nil
    }
}

// MARK: - Draggable overlay

/// One overlay with drag / pinch / rotate attached, plus a delete affordance
/// while it's selected.
private struct StoryOverlayHandle: View {
    @Binding var overlay: StoryOverlay
    let canvas: CGSize
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var dragStart: CGPoint?
    @State private var scaleStart: Double?
    @State private var rotationStart: Double?

    var body: some View {
        content
            .rotationEffect(.radians(overlay.rotation))
            .scaleEffect(overlay.scale)
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(.white))
                    }
                    .offset(x: 10, y: -10)
                }
            }
            .position(x: overlay.x * canvas.width, y: overlay.y * canvas.height)
            .gesture(dragGesture)
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(rotateGesture)
            .onTapGesture(count: 2) { onEdit() }
            .onTapGesture { onSelect() }
    }

    @ViewBuilder
    private var content: some View {
        switch overlay.kind {
        case .text:
            Text(overlay.text ?? "")
                .font(.system(size: overlay.fontScale * canvas.width, weight: .bold))
                .foregroundStyle(overlay.isLight ? Color.white : Color(hex: "111114"))
                .shadow(color: .black.opacity(overlay.isLight ? 0.4 : 0), radius: 8, y: 2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: canvas.width * 0.86)
        case .sticker:
            Group {
                if let data = overlay.imageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFit()
                } else {
                    MediaImage(url: overlay.imageURL, cornerRadius: 0).aspectRatio(1, contentMode: .fit)
                }
            }
            .frame(width: overlay.fontScale * canvas.width)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStart == nil {
                    dragStart = CGPoint(x: overlay.x, y: overlay.y)
                    onSelect()
                }
                guard let start = dragStart, canvas.width > 0, canvas.height > 0 else { return }
                overlay.x = min(max(start.x + value.translation.width / canvas.width, 0.04), 0.96)
                overlay.y = min(max(start.y + value.translation.height / canvas.height, 0.05), 0.95)
            }
            .onEnded { _ in dragStart = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if scaleStart == nil { scaleStart = overlay.scale }
                guard let start = scaleStart else { return }
                overlay.scale = min(max(start * value.magnification, 0.3), 4)
            }
            .onEnded { _ in scaleStart = nil }
    }

    private var rotateGesture: some Gesture {
        RotateGesture()
            .onChanged { value in
                if rotationStart == nil { rotationStart = overlay.rotation }
                guard let start = rotationStart else { return }
                overlay.rotation = start + value.rotation.radians
            }
            .onEnded { _ in rotationStart = nil }
    }
}

// MARK: - Text overlay editor

private struct StoryTextEditorSheet: View {
    @State var text: String
    @State var isLight: Bool
    let onSave: (String, Bool) -> Void
    let onDelete: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                GGColor.sheetBG.ignoresSafeArea()
                VStack(spacing: 18) {
                    TextField("Type something", text: $text, axis: .vertical)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .padding(.horizontal, 20)
                        .padding(.top, 30)

                    Picker("", selection: $isLight) {
                        Text("Light").tag(true)
                        Text("Dark").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 30)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Remove", role: .destructive) { onDelete() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onSave(text, isLight) }
                        .fontWeight(.semibold)
                }
            }
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.medium])
        .onAppear { focused = true }
    }
}
