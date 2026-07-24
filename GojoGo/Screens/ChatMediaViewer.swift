import SwiftUI
import AVKit
import Photos
import UIKit

/// Full-screen viewer for photos and videos shared in a chat.
///
/// Opens on tap, pages through a carousel, and offers the three things you'd
/// expect from a message attachment: save it to Photos, share it out, or send it
/// on to another conversation. Swipe down to dismiss, like the system viewer.
struct ChatMediaViewer: View {
    let items: [ChatMediaItem]
    var startIndex: Int = 0
    var onDismiss: () -> Void

    @EnvironmentObject var app: AppState
    @State private var index: Int
    @State private var dragOffset: CGSize = .zero
    @State private var chromeVisible = true
    @State private var sharePayload: SharePayload?
    @State private var forwarding = false
    @State private var status: SaveStatus?

    init(items: [ChatMediaItem], startIndex: Int = 0, onDismiss: @escaping () -> Void) {
        self.items = items
        self.startIndex = startIndex
        self.onDismiss = onDismiss
        _index = State(initialValue: min(max(startIndex, 0), max(items.count - 1, 0)))
    }

    private var current: ChatMediaItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    /// Fades the backdrop as the sheet is dragged away.
    private var backdropOpacity: Double {
        max(0.25, 1 - Double(abs(dragOffset.height)) / 500)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backdropOpacity)
                .ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    ChatMediaPage(item: item, isCurrent: i == index)
                        .tag(i)
                        .onTapGesture {
                            withAnimation(.ggSnappy) { chromeVisible.toggle() }
                        }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: dragOffset.height)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Vertical drags dismiss; horizontal belongs to the pager.
                        guard abs(value.translation.height) > abs(value.translation.width) else { return }
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        if abs(value.translation.height) > 140 || abs(value.predictedEndTranslation.height) > 300 {
                            onDismiss()
                        } else {
                            withAnimation(.ggSnappy) { dragOffset = .zero }
                        }
                    }
            )

            if chromeVisible {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.black.opacity(0.55), .clear],
                        startPoint: .top, endPoint: .bottom)
                        .frame(height: 110)
                        .allowsHitTesting(false)
                    Spacer(minLength: 0)
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.4)],
                        startPoint: .top, endPoint: .bottom)
                        .frame(height: 130)
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea()
                .transition(.opacity)

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if let status { statusPill(status) }
                    bottomBar
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.activityItems)
        }
        .sheet(isPresented: $forwarding) {
            ForwardToChatSheet(
                excluding: current?.messageID,
                onPick: { conversationID in
                    forwarding = false
                    forward(to: conversationID)
                },
                onCancel: { forwarding = false })
                .environmentObject(app)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground {
                    Rectangle().fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .overlay(Color.black.opacity(0.28))
                }
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glass(cornerRadius: 20, interactive: true)
            .environment(\.colorScheme, .dark)

            Spacer()

            if items.count > 1 {
                Text("\(index + 1) of \(items.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassCapsule(interactive: false, dense: true)
                    .environment(\.colorScheme, .dark)
            }

            Spacer()

            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var bottomBar: some View {
        HStack(spacing: 4) {
            actionButton("square.and.arrow.down", "Save") { save() }
            actionButton("square.and.arrow.up", "Share") { share() }
            actionButton("arrowshape.turn.up.right", "Send to") { forwarding = true }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .glass(cornerRadius: 28, interactive: true, floating: true)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private func actionButton(_ icon: String, _ title: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func statusPill(_ status: SaveStatus) -> some View {
        HStack(spacing: 8) {
            Image(systemName: status.icon)
                .font(.system(size: 13, weight: .semibold))
            Text(status.message)
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .glassCapsule(interactive: false, dense: true)
        .environment(\.colorScheme, .dark)
        .padding(.bottom, 12)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: Actions

    private func save() {
        guard let item = current else { return }
        Task {
            let result = await ChatMediaLibrary.save(item)
            withAnimation(.ggSnappy) { status = result }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.ggSnappy) { status = nil }
        }
    }

    private func share() {
        guard let item = current else { return }
        Task {
            guard let payload = await SharePayload.make(from: item) else {
                withAnimation(.ggSnappy) { status = .failed("Nothing to share yet") }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation(.ggSnappy) { status = nil }
                return
            }
            sharePayload = payload
        }
    }

    private func forward(to conversationID: UUID) {
        guard let item = current else { return }
        app.forwardWorldMedia(item, to: conversationID)
        onDismiss()
    }

    enum SaveStatus: Equatable {
        case saved
        case denied
        case failed(String)

        var message: String {
            switch self {
            case .saved: return "Saved to Photos"
            case .denied: return "Allow photo access in Settings"
            case .failed(let reason): return reason
            }
        }

        var icon: String {
            switch self {
            case .saved: return "checkmark.circle.fill"
            case .denied, .failed: return "exclamationmark.circle.fill"
            }
        }
    }
}

// MARK: - One page

private struct ChatMediaPage: View {
    let item: ChatMediaItem
    let isCurrent: Bool

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        if item.isVideo, let url = item.playableVideoURL {
            VideoPage(url: url, isCurrent: isCurrent)
        } else if item.isUnplayableVideo {
            unavailableVideo
        } else {
            photo
        }
    }

    /// Pinch to zoom, drag to pan, double-tap to toggle — the expected gestures.
    private var photo: some View {
        MediaImage(url: item.imageURL, data: item.imageData, cornerRadius: 0, contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in scale = min(max(lastScale * value, 1), 5) }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1 { resetZoom() }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard scale > 1 else { return }
                        offset = CGSize(width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height)
                    }
                    .onEnded { _ in lastOffset = offset }
            )
            .onTapGesture(count: 2) {
                withAnimation(.ggSnappy) {
                    if scale > 1 { resetZoom() } else { scale = 2.5; lastScale = 2.5 }
                }
            }
    }

    private func resetZoom() {
        scale = 1; lastScale = 1
        offset = .zero; lastOffset = .zero
    }

    /// Videos sent before the app carried the movie file have a poster only.
    private var unavailableVideo: some View {
        ZStack {
            MediaImage(url: item.imageURL, data: item.imageData, cornerRadius: 0, contentMode: .fit)
                .opacity(0.35)
            VStack(spacing: 10) {
                Image(systemName: "play.slash.fill")
                    .font(.system(size: 30))
                Text("This video wasn't uploaded")
                    .font(.system(size: 14, weight: .medium))
                Text("Only its preview was saved.")
                    .font(.system(size: 12))
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
        }
    }
}

/// AVPlayer page that only holds a player while it's the visible page.
private struct VideoPage: View {
    let url: URL
    let isCurrent: Bool

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().tint(.white)
            }
        }
        .onAppear { start() }
        .onDisappear { stop() }
        .onChange(of: isCurrent) { _, current in
            if current { start() } else { stop() }
        }
    }

    private func start() {
        guard isCurrent else { return }
        if player == nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = AVPlayer(url: url)
        }
        player?.play()
    }

    private func stop() {
        player?.pause()
        player = nil
    }
}

// MARK: - Save to Photos

enum ChatMediaLibrary {

    /// Saves a chat attachment to the user's library, fetching the bytes first
    /// when we only hold a URL. Add-only access, so we never gain read rights.
    static func save(_ item: ChatMediaItem) async -> ChatMediaViewer.SaveStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }

        do {
            if item.isVideo {
                guard let source = item.playableVideoURL else {
                    return .failed("This video wasn't uploaded")
                }
                let local = source.isFileURL ? source : try await download(source, extension: "mov")
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset()
                        .addResource(with: .video, fileURL: local, options: nil)
                }
            } else {
                guard let data = try await imageData(for: item) else {
                    return .failed("Couldn't load this photo")
                }
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset()
                        .addResource(with: .photo, data: data, options: nil)
                }
            }
            return .saved
        } catch {
            return .failed("Couldn't save")
        }
    }

    static func imageData(for item: ChatMediaItem) async throws -> Data? {
        if let data = item.imageData { return data }
        guard let url = item.remoteImageURL else { return nil }
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    /// Pulls a remote file into a temp location so it can be handed to Photos
    /// or the share sheet as a real file.
    static func download(_ url: URL, extension ext: String) async throws -> URL {
        let (temp, _) = try await URLSession.shared.download(from: url)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(ext)")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }
}

// MARK: - Share sheet

struct SharePayload: Identifiable {
    let id = UUID()
    let activityItems: [Any]

    /// Images share as a `UIImage`, videos as a file URL — what the share sheet
    /// needs to offer Save Video, AirDrop, Messages and the rest.
    static func make(from item: ChatMediaItem) async -> SharePayload? {
        if item.isVideo {
            guard let source = item.playableVideoURL else { return nil }
            if source.isFileURL { return SharePayload(activityItems: [source]) }
            guard let local = try? await ChatMediaLibrary.download(source, extension: "mov") else {
                return nil
            }
            return SharePayload(activityItems: [local])
        }
        // `try?` flattens the throwing call's optional Data, so one bind is enough.
        guard let data = try? await ChatMediaLibrary.imageData(for: item),
              let image = UIImage(data: data) else { return nil }
        return SharePayload(activityItems: [image])
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Forward to another conversation

/// Conversation picker for "Send to" — forwards the attachment into another
/// My World thread.
struct ForwardToChatSheet: View {
    var excluding: UUID?
    var onPick: (UUID) -> Void
    var onCancel: () -> Void

    @EnvironmentObject var app: AppState
    @State private var query = ""

    private var conversations: [WorldConversation] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = app.worldConversations.sorted { $0.lastActivityAt > $1.lastActivityAt }
        guard !q.isEmpty else { return all }
        return all.filter { $0.title.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(conversations) { convo in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onPick(convo.id)
                        } label: {
                            row(convo)
                        }
                        .buttonStyle(PressableStyle())
                    }

                    if conversations.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(IMColor.secondary)
                            Text("No conversations")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(IMColor.secondary)
                        }
                        .padding(.vertical, 48)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
    }

    private var header: some View {
        ZStack {
            Text("Send to")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(IMColor.label)
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(IMColor.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassCapsule(interactive: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(IMColor.secondary)
            TextField("Search", text: $query)
                .font(.system(size: 16))
                .foregroundStyle(IMColor.label)
                .tint(IMColor.blue)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glass(cornerRadius: 16, interactive: true)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private func row(_ convo: WorldConversation) -> some View {
        HStack(spacing: 12) {
            if convo.isGroup {
                Circle()
                    .fill(IMColor.chrome.opacity(0.85))
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(IMColor.label.opacity(0.8))
                    )
                    .overlay(Circle().strokeBorder(IMColor.label.opacity(0.08), lineWidth: 0.5))
            } else {
                UserAvatar(size: 46, gradient: convo.avatarGradient,
                           letter: String(convo.title.prefix(1)), imageURL: convo.avatarURL)
                    .overlay(Circle().strokeBorder(IMColor.label.opacity(0.08), lineWidth: 0.5))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(convo.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(IMColor.label)
                    .lineLimit(1)
                Text(convo.preview)
                    .font(.system(size: 13))
                    .foregroundStyle(IMColor.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(IMColor.blue))
                .shadow(color: IMColor.blue.opacity(0.35), radius: 8, y: 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .glass(cornerRadius: 18, interactive: true)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
