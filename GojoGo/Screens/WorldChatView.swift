import SwiftUI
import PhotosUI
import MapKit
import AVFoundation
import UIKit

/// iMessage-style conversation thread + Apps drawer.
struct WorldChatView: View {
    @EnvironmentObject var app: AppState
    let conversationID: UUID
    @FocusState private var focused: Bool
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showRecorder = false
    /// Interactive swipe-to-dismiss (finger moves left → chat slides off).
    @State private var dismissDrag: CGFloat = 0

    private var live: WorldConversation {
        app.worldConversations.first(where: { $0.id == conversationID })
            ?? WorldConversation(title: "", preview: "", timeAgo: "")
    }

    private var isTyping: Bool {
        app.worldTypingConversationID == conversationID
    }

    private var canSend: Bool {
        !app.worldDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !app.worldPendingAttachments.isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(spacing: 0) {
                chatHeader
                messageScroll
                composer
            }

            if app.showWorldAppsMenu {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                            app.showWorldAppsMenu = false
                        }
                    }
                WorldAppsDrawer { action in
                    handleDrawer(action)
                }
                .padding(.leading, 12)
                .padding(.bottom, 66)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92, anchor: .bottomLeading).combined(with: .opacity),
                    removal: .opacity))
            }
        }
        .offset(x: dismissDrag)
        .opacity(Double(max(0.45, 1 - abs(dismissDrag) / 280)))
        .background {
            // Right-edge swipe only — never fights vertical scrolling in the thread.
            SwipeLeftDismissBridge(
                offset: $dismissDrag,
                onDismiss: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    DispatchQueue.main.async {
                        app.closeWorldConversation()
                    }
                }
            )
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: app.showWorldAppsMenu)
        .background(IMColor.bg.ignoresSafeArea())
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoItems,
            maxSelectionCount: 6,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await stagePickedMedia(items); photoItems = [] }
        }
        .sheet(isPresented: $showRecorder) {
            AudioRecorderSheet { _, label, _ in
                app.sendWorldAudio(durationLabel: label)
            }
        }
    }

    // MARK: Drawer actions

    private func handleDrawer(_ action: WorldAppAction) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
            app.showWorldAppsMenu = false
        }
        switch action {
        case .camera, .photos:
            showPhotoPicker = true
        case .audio:
            showRecorder = true
        case .stickers:
            app.sendWorldSticker(["😂", "🔥", "❤️", "👀", "🥳", "😮", "😎"].randomElement() ?? "❤️")
        case .location:
            app.sendWorldLocation()
        case .polls, .sendLater:
            break // not in the prototype
        }
    }

    /// Loads picked media and stages it in the composer tray (iMessage-style) instead of sending.
    private func stagePickedMedia(_ items: [PhotosPickerItem]) async {
        for item in items {
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }

            if isVideo {
                if let att = await Self.videoAttachment(from: data) {
                    await MainActor.run { app.stageWorldAttachment(att) }
                }
            } else if let ui = UIImage(data: data),
                      let jpeg = ui.ggDownscaled(maxDimension: 1200).jpegData(compressionQuality: 0.8) {
                await MainActor.run {
                    app.stageWorldAttachment(WorldPendingAttachment(imageData: jpeg))
                }
            }
        }
    }

    /// Writes the video to a temp file to grab a poster frame + duration.
    private static func videoAttachment(from data: Data) async -> WorldPendingAttachment? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("world-video-\(UUID().uuidString).mov")
        do { try data.write(to: url) } catch { return nil }
        defer { try? FileManager.default.removeItem(at: url) }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 900, height: 900)

        guard let cg = try? generator.copyCGImage(
            at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil),
              let poster = UIImage(cgImage: cg).jpegData(compressionQuality: 0.8)
        else { return nil }

        let seconds = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        let label = String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
        return WorldPendingAttachment(imageData: poster, isVideo: true, durationLabel: label)
    }

    // MARK: Header

    private var chatHeader: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                app.closeWorldConversation()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                    if app.worldUnreadCount > 0 {
                        Text("\(min(app.worldUnreadCount, 99))")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(IMColor.chrome))
                    }
                }
                .foregroundStyle(IMColor.blue)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                app.openWorldContact()
            } label: {
                VStack(spacing: 4) {
                    avatar(size: 42)
                    HStack(spacing: 2) {
                        Text(live.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(IMColor.label)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(IMColor.secondary)
                    }
                }
                .frame(maxWidth: 180)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button { } label: {
                Image(systemName: "video")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(IMColor.blue)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Video call")
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
        .background(
            LinearGradient(
                colors: [IMColor.bg, IMColor.bg.opacity(0.92), IMColor.bg.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 90)
            .ignoresSafeArea(edges: .top),
            alignment: .top
        )
    }

    @ViewBuilder
    private func avatar(size: CGFloat) -> some View {
        if live.isGroup {
            Circle()
                .fill(IMColor.chrome)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "person.2.fill")
                        .font(.system(size: size * 0.38))
                        .foregroundStyle(.white.opacity(0.8))
                )
        } else {
            UserAvatar(
                size: size,
                gradient: live.avatarGradient,
                letter: String(live.title.prefix(1)),
                imageURL: live.avatarURL
            )
        }
    }

    // MARK: Messages

    private var messageScroll: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(live.messages.enumerated()), id: \.element.id) { index, msg in
                        messageRow(msg, index: index)
                            .id(msg.id)
                            .transition(.messageBubble(fromUser: msg.fromUser))
                    }
                    if isTyping {
                        typingRow
                            .id("typing")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .animation(.spring(response: 0.42, dampingFraction: 0.68), value: live.messages.count)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: live.messages.count) { _, _ in
                scrollToEnd(proxy)
            }
            .onChange(of: isTyping) { _, typing in
                if typing {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
            .onAppear { scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let last = live.messages.last else { return }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var typingRow: some View {
        HStack {
            TypingIndicatorBubble()
            Spacer(minLength: 60)
        }
        .padding(.vertical, 3)
        .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
    }

    @ViewBuilder
    private func messageRow(_ msg: WorldMessage, index: Int) -> some View {
        let next = index + 1 < live.messages.count ? live.messages[index + 1] : nil
        let isLastInCluster = next == nil
            || !next!.kind.isBubble
            || next!.fromUser != msg.fromUser

        switch msg.kind {
        case .timestamp:
            Text(msg.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(IMColor.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)

        case .system:
            Text(msg.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(IMColor.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)

        case .emoji:
            bubbleLine(msg, spacing: 60) {
                Text(msg.text)
                    .font(.system(size: 54))
            }

        case .file:
            bubbleLine(msg) {
                fileBubble(msg, tailed: isLastInCluster)
            }

        case .photo, .video:
            bubbleLine(msg) {
                photoBubble(msg)
            }

        case .carousel:
            bubbleLine(msg) {
                carouselBubble(msg)
            }

        case .audio:
            bubbleLine(msg) {
                audioBubble(msg, tailed: isLastInCluster)
            }

        case .location:
            bubbleLine(msg) {
                locationBubble(msg)
            }

        case .text:
            bubbleLine(msg) {
                textBubble(msg, tailed: isLastInCluster)
            }
        }
    }

    /// Shared incoming/outgoing alignment + sender name + read receipt.
    private func bubbleLine<Content: View>(
        _ msg: WorldMessage, spacing: CGFloat = 48,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: msg.fromUser ? .trailing : .leading, spacing: 3) {
            if !msg.fromUser, live.isGroup, let sender = msg.senderName {
                Text(sender)
                    .font(.system(size: 11))
                    .foregroundStyle(IMColor.secondary)
                    .padding(.leading, 14)
            }
            HStack {
                if msg.fromUser { Spacer(minLength: spacing) }
                content()
                if !msg.fromUser { Spacer(minLength: spacing) }
            }
            if let read = msg.readLabel {
                Text(read)
                    .font(.system(size: 11))
                    .foregroundStyle(IMColor.secondary)
                    .padding(.trailing, msg.fromUser ? 4 : 0)
                    .padding(.leading, msg.fromUser ? 0 : 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.vertical, 1)
    }

    private func textBubble(_ msg: WorldMessage, tailed: Bool) -> some View {
        Text(msg.text)
            .font(.system(size: 17))
            .foregroundStyle(msg.fromUser ? Color.white : IMColor.label)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                BubbleShape(fromUser: msg.fromUser, tailed: tailed)
                    .fill(msg.fromUser ? IMColor.blue : IMColor.bubbleGray)
            )
    }

    private func photoBubble(_ msg: WorldMessage) -> some View {
        MediaImage(data: msg.imageData, cornerRadius: 18)
            .frame(maxWidth: 240)
            .frame(height: 260)
            .overlay {
                if msg.kind == .video {
                    Image(systemName: "play.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.45))
                        .font(.system(size: 44))
                }
            }
            .overlay(alignment: .bottomLeading) {
                if msg.kind == .video, let d = msg.durationLabel {
                    Text(d)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(IMColor.label)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .padding(8)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(IMColor.label.opacity(0.08), lineWidth: 0.5)
            )
    }

    private func carouselBubble(_ msg: WorldMessage) -> some View {
        ChatCarouselBubble(items: msg.carouselItems)
    }

    private func audioBubble(_ msg: WorldMessage, tailed: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "play.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(msg.fromUser ? Color.white : IMColor.label)
            Image(systemName: "waveform")
                .font(.system(size: 22))
                .foregroundStyle((msg.fromUser ? Color.white : IMColor.label).opacity(0.9))
            Text(msg.durationLabel ?? "0:03")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle((msg.fromUser ? Color.white : IMColor.label).opacity(0.9))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            BubbleShape(fromUser: msg.fromUser, tailed: tailed)
                .fill(msg.fromUser ? IMColor.blue : IMColor.bubbleGray)
        )
    }

    private func locationBubble(_ msg: WorldMessage) -> some View {
        let lat = app.selectedWorldContact?.latitude ?? 33.5731
        let lon = app.selectedWorldContact?.longitude ?? -7.5898
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let region = MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )

        return VStack(alignment: .leading, spacing: 0) {
            Map(initialPosition: .region(region)) {
                Annotation("", coordinate: coord) {
                    Image(systemName: "mappin.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, IMColor.blue)
                        .font(.system(size: 26))
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
            .frame(width: 230, height: 130)
            .disabled(true)

            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(IMColor.blue)
                Text(msg.text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(IMColor.label)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 230, alignment: .leading)
            .background(IMColor.bubbleGray)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(IMColor.label.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func fileBubble(_ msg: WorldMessage, tailed: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.system(size: 22))
                .foregroundStyle(IMColor.blue)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(IMColor.label.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Text(msg.fileName ?? "Attachment")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(msg.fromUser ? Color.white : IMColor.label)
                    .lineLimit(1)
                Text(msg.fileMeta ?? "Document")
                    .font(.system(size: 13))
                    .foregroundStyle(IMColor.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 280)
        .background(
            BubbleShape(fromUser: msg.fromUser, tailed: tailed)
                .fill(msg.fromUser ? IMColor.blue.opacity(0.85) : IMColor.bubbleGray)
        )
    }

    // MARK: Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                focused = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                    app.showWorldAppsMenu.toggle()
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(IMColor.label)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(IMColor.chrome))
                    .rotationEffect(.degrees(app.showWorldAppsMenu ? 45 : 0))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Apps")

            VStack(alignment: .leading, spacing: 0) {
                if !app.worldPendingAttachments.isEmpty {
                    attachmentTray

                    Rectangle()
                        .fill(IMColor.label.opacity(0.08))
                        .frame(height: 0.66)
                }

                HStack(alignment: .bottom, spacing: 6) {
                    TextField("iMessage", text: $app.worldDraft, axis: .vertical)
                        .font(.system(size: 17))
                        .foregroundStyle(IMColor.label)
                        .lineLimit(1...5)
                        .focused($focused)
                        .tint(IMColor.blue)
                        .padding(.leading, 16)
                        .padding(.vertical, 10)

                    if canSend {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            app.sendWorldMessage()
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(width: 50, height: 34)
                                .background(Capsule().fill(IMColor.blue))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 4)
                        .padding(.bottom, 4)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Send")
                    } else {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showRecorder = true
                        } label: {
                            Image(systemName: "waveform")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(IMColor.label.opacity(0.6))
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                        .padding(.bottom, 4)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Record audio message")
                    }
                }
                .frame(minHeight: 42)
            }
            .background(
                RoundedRectangle(cornerRadius: app.worldPendingAttachments.isEmpty ? 21 : 26,
                                 style: .continuous)
                    .fill(IMColor.inputFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: app.worldPendingAttachments.isEmpty ? 21 : 26,
                                         style: .continuous)
                            .strokeBorder(IMColor.label.opacity(0.09), lineWidth: 0.66)
                    )
            )
            .animation(.easeOut(duration: 0.15), value: canSend)
            .animation(.spring(response: 0.35, dampingFraction: 0.86),
                       value: app.worldPendingAttachments.count)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(IMColor.bg)
        .safeAreaPadding(.bottom, 0)
    }

    /// Staged photos/videos shown above the text row, iMessage-style.
    private var attachmentTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(app.worldPendingAttachments) { att in
                    ZStack(alignment: .topTrailing) {
                        MediaImage(data: att.imageData, cornerRadius: 14)
                            .frame(width: 104, height: 148)
                            .overlay {
                                if att.isVideo {
                                    Image(systemName: "play.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.45))
                                        .font(.system(size: 30))
                                }
                            }
                            .overlay(alignment: .bottomLeading) {
                                if att.isVideo, let d = att.durationLabel {
                                    Text(d)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.black.opacity(0.55)))
                                        .padding(6)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(IMColor.label.opacity(0.1), lineWidth: 0.5)
                            )

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            app.removeWorldAttachment(att.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color(white: 0.25).opacity(0.9))
                                .font(.system(size: 22))
                                .frame(width: 34, height: 34)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                        .accessibilityLabel("Remove attachment")
                    }
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)
        }
    }
}

private extension WorldMessageKind {
    /// Kinds that render as chat bubbles and participate in tail clustering.
    var isBubble: Bool {
        switch self {
        case .text, .file, .emoji, .photo, .video, .carousel, .audio, .location: return true
        case .system, .timestamp: return false
        }
    }
}

// MARK: - Chat media carousel

private struct ChatCarouselBubble: View {
    let items: [WorldCarouselItem]
    @State private var page = 0

    private let width: CGFloat = 240
    private let height: CGFloat = 280

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $page) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ZStack {
                        MediaImage(data: item.imageData, cornerRadius: 0)
                            .frame(width: width, height: height)
                            .clipped()

                        if item.isVideo {
                            Image(systemName: "play.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.45))
                                .font(.system(size: 44))

                            if let d = item.durationLabel {
                                Text(d)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.black.opacity(0.55)))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                                    .padding(8)
                            }
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(width: width, height: height)

            if items.count > 1 {
                Text("\(page + 1)/\(items.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(8)
            }

            if items.count > 1 {
                HStack(spacing: 4) {
                    ForEach(0..<items.count, id: \.self) { i in
                        Circle()
                            .fill(i == page ? Color.white : Color.white.opacity(0.4))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 10)
                .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(IMColor.label.opacity(0.08), lineWidth: 0.5)
        )
    }
}

private extension UIImage {
    func ggDownscaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

// MARK: - Typing indicator

private struct TypingIndicatorBubble: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(IMColor.secondary)
                    .frame(width: 8, height: 8)
                    .opacity(phase == i ? 1 : 0.35)
                    .scaleEffect(phase == i ? 1.15 : 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            BubbleShape(fromUser: false, tailed: true)
                .fill(IMColor.bubbleGray)
        )
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                withAnimation(.easeInOut(duration: 0.3)) { phase = (phase + 1) % 3 }
            }
        }
    }
}

// MARK: - Swipe-to-dismiss (left-edge → right — no scroll conflict)

/// Starts only from the left screen edge, so up/down scrolling in the chat is untouched.
private struct SwipeLeftDismissBridge: UIViewRepresentable {
    @Binding var offset: CGFloat
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(offset: $offset, onDismiss: onDismiss)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        context.coordinator.attach(from: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.offset = $offset
        context.coordinator.onDismiss = onDismiss
        context.coordinator.attach(from: uiView)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var offset: Binding<CGFloat>
        var onDismiss: () -> Void
        private weak var host: UIView?
        private var edgePan: UIScreenEdgePanGestureRecognizer?

        init(offset: Binding<CGFloat>, onDismiss: @escaping () -> Void) {
            self.offset = offset
            self.onDismiss = onDismiss
        }

        func attach(from anchor: UIView) {
            DispatchQueue.main.async { [weak self, weak anchor] in
                guard let self, let anchor else { return }
                guard let host = anchor.window ?? Self.nearestHost(from: anchor) else { return }
                if self.host === host, self.edgePan != nil { return }
                if let old = self.edgePan { self.host?.removeGestureRecognizer(old) }

                let edge = UIScreenEdgePanGestureRecognizer(
                    target: self, action: #selector(handleEdge(_:)))
                edge.edges = .left
                edge.delegate = self
                host.addGestureRecognizer(edge)
                self.edgePan = edge
                self.host = host
            }
        }

        private static func nearestHost(from view: UIView) -> UIView? {
            var current: UIView? = view.superview
            while let c = current {
                if c.bounds.width > 200, c.bounds.height > 200 { return c }
                current = c.superview
            }
            return view.window
        }

        @objc func handleEdge(_ g: UIScreenEdgePanGestureRecognizer) {
            guard let view = g.view else { return }
            // Edge pan from the left: translation.x is ≥ 0 as the finger moves right.
            let t = g.translation(in: view)
            let vel = g.velocity(in: view)

            switch g.state {
            case .changed:
                offset.wrappedValue = min(max(t.x, 0), view.bounds.width)
            case .ended, .cancelled:
                let shouldDismiss = t.x > 90 || vel.x > 500
                if shouldDismiss {
                    UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn) {
                        self.offset.wrappedValue = UIScreen.main.bounds.width
                    } completion: { _ in
                        self.onDismiss()
                        self.offset.wrappedValue = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        offset.wrappedValue = 0
                    }
                }
            default:
                break
            }
        }
    }
}
// MARK: - Bubble shape (iMessage tails)

struct BubbleShape: Shape {
    var fromUser: Bool
    var tailed: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18
        let tail: CGFloat = tailed ? 4 : r
        var path = Path()
        if fromUser {
            path.addRoundedRect(
                in: rect,
                cornerRadii: RectangleCornerRadii(
                    topLeading: r, bottomLeading: r,
                    bottomTrailing: tail, topTrailing: r
                ),
                style: .continuous
            )
        } else {
            path.addRoundedRect(
                in: rect,
                cornerRadii: RectangleCornerRadii(
                    topLeading: r, bottomLeading: tail,
                    bottomTrailing: r, topTrailing: r
                ),
                style: .continuous
            )
        }
        return path
    }
}

// MARK: - Send / receive bubble pop-in

private struct MessageBubbleAppear: ViewModifier {
    var fromUser: Bool
    var amount: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(amount, anchor: fromUser ? .bottomTrailing : .bottomLeading)
            .opacity(Double(amount))
            .offset(y: (1 - amount) * 14)
            .offset(x: fromUser ? (1 - amount) * 18 : (1 - amount) * -18)
    }
}

private extension AnyTransition {
    /// Pops in from the composer (outgoing) or from the left (incoming), like iMessage.
    static func messageBubble(fromUser: Bool) -> AnyTransition {
        .modifier(
            active: MessageBubbleAppear(fromUser: fromUser, amount: 0.55),
            identity: MessageBubbleAppear(fromUser: fromUser, amount: 1)
        )
        .combined(with: .opacity)
    }
}

// MARK: - Apps drawer (+ menu)

enum WorldAppAction {
    case camera, photos, stickers, polls, audio, sendLater, location
}

struct WorldAppsDrawer: View {
    var onSelect: (WorldAppAction) -> Void = { _ in }

    private let rows: [(title: String, icon: String, color: Color, action: WorldAppAction)] = [
        ("Camera", "camera.fill", Color(white: 0.35), .camera),
        ("Photos", "photo.on.rectangle.angled", Color(red: 0.95, green: 0.35, blue: 0.55), .photos),
        ("Stickers", "face.smiling.inverse", IMColor.blue, .stickers),
        ("Polls", "chart.bar.fill", Color(red: 1, green: 0.8, blue: 0.2), .polls),
        ("Audio", "waveform", Color(red: 1, green: 0.27, blue: 0.23), .audio),
        ("Send Later", "clock.badge", Color(red: 0.4, green: 0.75, blue: 1), .sendLater),
        ("Location", "location.fill", Color(red: 0.2, green: 0.78, blue: 0.35), .location),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSelect(row.action)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: row.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(row.color))
                        Text(row.title)
                            .font(.system(size: 17))
                            .foregroundStyle(IMColor.label)
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < rows.count - 1 {
                    Divider().background(IMColor.label.opacity(0.08)).padding(.leading, 60)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(width: 230)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(IMColor.chrome.opacity(0.95))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(IMColor.label.opacity(0.1), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
    }
}
