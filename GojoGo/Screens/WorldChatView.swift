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
    /// Frame of each bubble in the chat coordinate space (for the tapback overlay).
    @State private var bubbleFrames: [UUID: CGRect] = [:]

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
            chatWallpaper

            VStack(spacing: 0) {
                chatHeader
                messageScroll
                composer
            }

            reactionOverlay
            pollComposerOverlay
            sendLaterPickerOverlay

            if app.showWorldAppsMenu {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.ggNav) {
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
        .animation(.ggNav, value: app.showWorldAppsMenu)
        .coordinateSpace(name: "worldChat")
        .onPreferenceChange(BubbleFrameKey.self) { bubbleFrames = $0 }
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
        withAnimation(.ggNav) {
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
        case .polls:
            withAnimation(.ggNav) {
                app.showWorldPollOverlay = true
            }
        case .sendLater:
            app.worldSendLaterDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            app.setWorldSendLater(Self.sendLaterLabel(for: app.worldSendLaterDate))
        }
    }

    static func sendLaterLabel(for date: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(date) { return "Today \(time)" }
        if cal.isDateInTomorrow(date) { return "Tomorrow \(time)" }
        let day = date.formatted(.dateTime.weekday(.wide))
        return "\(day) \(time)"
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

    // MARK: Wallpaper

    @ViewBuilder
    private var chatWallpaper: some View {
        let stops = live.background.gradient
        if stops.isEmpty {
            IMColor.bg.ignoresSafeArea()
        } else {
            LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.06).ignoresSafeArea())
        }
    }

    // MARK: Tapback / action overlay

    @ViewBuilder
    private var reactionOverlay: some View {
        if let target = app.worldReactionTarget,
           let msg = live.messages.first(where: { $0.id == target }) {
            let frame = bubbleFrames[target]
                ?? CGRect(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2,
                          width: 180, height: 44)
            WorldReactionOverlay(
                message: msg,
                bubbleFrame: frame,
                existingUserTapback: msg.reactions.first(where: { $0.fromUser })?.tapback,
                onTapback: { app.toggleWorldReaction($0, on: target) },
                onReply: { app.beginWorldReply(to: target); focused = true },
                onCopy: { app.copyWorldMessage(target) },
                onDelete: { app.deleteWorldMessage(target) },
                onDismiss: { app.worldReactionTarget = nil }
            ) {
                bubbleContent(msg, tailed: true)
            }
            .transition(.opacity)
            .zIndex(50)
        }
    }

    // MARK: Poll composer / Send-Later overlays (in-view — sheets don't present here)

    @ViewBuilder
    private var pollComposerOverlay: some View {
        if app.showWorldPollOverlay {
            WorldOverlaySheet(
                onDismiss: {
                    withAnimation(.ggNav) {
                        app.showWorldPollOverlay = false
                    }
                }
            ) {
                WorldPollComposer(
                    onSend: { q, opts in app.sendWorldPoll(question: q, options: opts) },
                    onCancel: {
                        withAnimation(.ggNav) {
                            app.showWorldPollOverlay = false
                        }
                    }
                )
                .frame(height: 460)
            }
            .zIndex(60)
        }
    }

    @ViewBuilder
    private var sendLaterPickerOverlay: some View {
        if app.showWorldSendLaterOverlay {
            WorldOverlaySheet(
                onDismiss: {
                    withAnimation(.ggNav) {
                        app.showWorldSendLaterOverlay = false
                    }
                }
            ) {
                VStack(spacing: 16) {
                    Text("Send Later")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(IMColor.label)
                        .padding(.top, 18)
                    DatePicker("", selection: $app.worldSendLaterDate, in: Date()...,
                               displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                        .tint(IMColor.blue)
                        .padding(.horizontal, 16)
                        .onChange(of: app.worldSendLaterDate) { _, newValue in
                            app.setWorldSendLater(Self.sendLaterLabel(for: newValue))
                        }
                    Button {
                        app.setWorldSendLater(Self.sendLaterLabel(for: app.worldSendLaterDate))
                        withAnimation(.ggNav) {
                            app.showWorldSendLaterOverlay = false
                        }
                    } label: {
                        Text("Done")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Capsule().fill(IMColor.blue))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .frame(height: 420)
            }
            .zIndex(60)
        }
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
                .animation(.ggSnappy, value: live.messages.count)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: live.messages.count) { _, _ in
                scrollToEnd(proxy)
            }
            .onChange(of: isTyping) { _, typing in
                if typing {
                    withAnimation(.ggSnappy) {
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
            withAnimation(.ggNav) {
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

        default:
            bubbleLine(msg, spacing: msg.kind == .emoji ? 60 : 48, tailed: isLastInCluster)
        }
    }

    /// Inner bubble body for a message — reused inline and inside the tapback overlay.
    @ViewBuilder
    private func bubbleContent(_ msg: WorldMessage, tailed: Bool) -> some View {
        switch msg.kind {
        case .emoji:
            Text(msg.text).font(.system(size: 54))
        case .file:
            fileBubble(msg, tailed: tailed)
        case .photo, .video:
            photoBubble(msg)
        case .carousel:
            carouselBubble(msg)
        case .audio:
            audioBubble(msg, tailed: tailed)
        case .location:
            locationBubble(msg)
        case .poll:
            pollBubble(msg)
        case .text:
            textBubble(msg, tailed: tailed)
        case .system, .timestamp:
            EmptyView()
        }
    }

    /// Shared incoming/outgoing alignment + reply snippet + reactions + receipt.
    private func bubbleLine(
        _ msg: WorldMessage, spacing: CGFloat = 48, tailed: Bool
    ) -> some View {
        VStack(alignment: msg.fromUser ? .trailing : .leading, spacing: 3) {
            if !msg.fromUser, live.isGroup, let sender = msg.senderName {
                Text(sender)
                    .font(.system(size: 11))
                    .foregroundStyle(IMColor.secondary)
                    .padding(.leading, 14)
            }

            if let reply = msg.replyTo {
                replySnippet(reply, fromUser: msg.fromUser)
            }

            HStack {
                if msg.fromUser { Spacer(minLength: spacing) }
                bubbleContent(msg, tailed: tailed)
                    .opacity(app.worldReactionTarget == msg.id ? 0 : 1)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: BubbleFrameKey.self,
                                value: [msg.id: proxy.frame(in: .named("worldChat"))])
                        }
                    )
                    .overlay(alignment: msg.fromUser ? .topLeading : .topTrailing) {
                        if !msg.reactions.isEmpty {
                            ReactionBadge(reactions: msg.reactions, fromUser: msg.fromUser)
                                .offset(x: msg.fromUser ? -10 : 10, y: -14)
                        }
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.3)
                            .onEnded { _ in
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                focused = false
                                withAnimation(.ggNav) {
                                    app.worldReactionTarget = msg.id
                                }
                            }
                    )
                if !msg.fromUser { Spacer(minLength: spacing) }
            }

            if let scheduled = msg.scheduledLabel {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Scheduled · \(scheduled)")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(IMColor.blue)
                .padding(.trailing, msg.fromUser ? 4 : 0)
                .transition(.opacity)
            } else if let read = msg.readLabel {
                Text(read)
                    .font(.system(size: 11))
                    .foregroundStyle(IMColor.secondary)
                    .padding(.trailing, msg.fromUser ? 4 : 0)
                    .padding(.leading, msg.fromUser ? 0 : 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.vertical, msg.reactions.isEmpty ? 1 : 8)
    }

    /// Quoted snippet shown above an inline reply, iMessage-style.
    private func replySnippet(_ reply: WorldReplySnippet, fromUser: Bool) -> some View {
        HStack {
            if fromUser { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 2) {
                Text(reply.authorName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(IMColor.secondary)
                Text(reply.preview)
                    .font(.system(size: 13))
                    .foregroundStyle(IMColor.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(IMColor.bubbleGray.opacity(0.55))
            )
            .overlay(alignment: fromUser ? .trailing : .leading) {
                Capsule()
                    .fill(IMColor.secondary.opacity(0.5))
                    .frame(width: 3, height: 20)
                    .offset(x: fromUser ? 6 : -6)
            }
            if !fromUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 6)
        .opacity(0.9)
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

    private func pollBubble(_ msg: WorldMessage) -> some View {
        WorldPollBubble(
            poll: msg.poll ?? WorldPoll(question: msg.text, options: []),
            fromUser: msg.fromUser,
            onVote: { app.voteWorldPoll(messageID: msg.id, optionID: $0) },
            onAddOption: { app.addWorldPollOption(messageID: msg.id, text: $0) }
        )
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 8) {
            if app.worldReplyingTo != nil { replyBar }
            if let label = app.worldSendLaterLabel { sendLaterBar(label) }
            composerRow
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(IMColor.bg)
        .safeAreaPadding(.bottom, 0)
        .animation(.ggNav, value: app.worldReplyingTo)
        .animation(.ggNav, value: app.worldSendLaterLabel)
    }

    /// Quoted-message bar shown above the composer when replying.
    private var replyBar: some View {
        HStack(spacing: 10) {
            Capsule().fill(IMColor.blue).frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Replying to \(replyTargetName)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IMColor.secondary)
                Text(replyTargetPreview)
                    .font(.system(size: 13))
                    .foregroundStyle(IMColor.label)
                    .lineLimit(1)
            }
            Spacer()
            Button { app.clearWorldReply() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(IMColor.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(IMColor.inputFill))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var replyTargetName: String {
        guard let rid = app.worldReplyingTo,
              let src = live.messages.first(where: { $0.id == rid }) else { return "" }
        return src.fromUser ? "You" : (src.senderName ?? live.title)
    }

    private var replyTargetPreview: String {
        guard let rid = app.worldReplyingTo,
              let src = live.messages.first(where: { $0.id == rid }) else { return "" }
        return src.snippetText
    }

    /// Scheduled-send bar shown above the composer (Send Later).
    private func sendLaterBar(_ label: String) -> some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.ggNav) {
                    app.showWorldSendLaterOverlay = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 13, weight: .semibold))
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(IMColor.blue)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { app.setWorldSendLater(nil) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(IMColor.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(IMColor.inputFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(IMColor.blue.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var composerRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                focused = false
                withAnimation(.ggNav) {
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
                    TextField(app.worldSendLaterLabel == nil ? "iMessage" : "Send Later",
                              text: $app.worldDraft, axis: .vertical)
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
            .animation(.ggSnappy, value: canSend)
            .animation(.ggNav,
                       value: app.worldPendingAttachments.count)
        }
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
        case .text, .file, .emoji, .photo, .video, .carousel, .audio, .location, .poll: return true
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
                withAnimation(.ggOverlay) { phase = (phase + 1) % 3 }
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
                    withAnimation(.ggNav) {
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
        .liquidGlass(cornerRadius: 28, interactive: false)
    }
}

// MARK: - In-view bottom-sheet overlay (used where UIKit sheets can't present)

struct WorldOverlaySheet<Content: View>: View {
    var onDismiss: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(appeared ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            content()
                .frame(maxWidth: .infinity)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 22, bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0, topTrailingRadius: 22, style: .continuous)
                        .fill(IMColor.sheetBG)
                        .ignoresSafeArea(edges: .bottom)
                )
                .overlay(alignment: .top) {
                    Capsule().fill(IMColor.secondary.opacity(0.5))
                        .frame(width: 36, height: 5)
                        .padding(.top, 8)
                }
                .offset(y: appeared ? 0 : 600)
        }
        .onAppear {
            withAnimation(.ggNav) { appeared = true }
        }
    }
}

// MARK: - Bubble frame reporting (for the tapback overlay)

struct BubbleFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Tapback badge stuck to a bubble corner

struct ReactionBadge: View {
    let reactions: [WorldReaction]
    let fromUser: Bool

    var body: some View {
        // Show the most recent one prominently; iMessage stacks, we keep it clean.
        HStack(spacing: -6) {
            ForEach(reactions.suffix(2)) { r in
                Image(systemName: r.tapback.badgeSymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(r.tapback == .heart
                                     ? Color(red: 1, green: 0.27, blue: 0.35)
                                     : (r.fromUser ? Color.white : IMColor.label))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(r.fromUser ? IMColor.blue : IMColor.bubbleGray)
                            .overlay(Circle().strokeBorder(IMColor.bg, lineWidth: 1.5))
                    )
            }
        }
    }
}

// MARK: - Long-press tapback + action overlay

struct WorldReactionOverlay<Bubble: View>: View {
    let message: WorldMessage
    let bubbleFrame: CGRect
    let existingUserTapback: WorldTapback?
    var onTapback: (WorldTapback) -> Void
    var onReply: () -> Void
    var onCopy: () -> Void
    var onDelete: () -> Void
    var onDismiss: () -> Void
    @ViewBuilder var bubble: () -> Bubble

    @State private var appeared = false

    private var fromUser: Bool { message.fromUser }

    /// Keep the lifted bubble on-screen even when the original sits under the tapback bar.
    private var bubbleY: CGFloat {
        let minY: CGFloat = 190
        let maxY = UIScreen.main.bounds.height - 240
        return min(max(bubbleFrame.midY, minY), maxY)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .ignoresSafeArea()
                .opacity(appeared ? 1 : 0)
                .onTapGesture { onDismiss() }

            // Tapback picker bar
            tapbackBar
                .position(x: barX, y: bubbleY - bubbleFrame.height / 2 - 44)
                .scaleEffect(appeared ? 1 : 0.6, anchor: .bottom)
                .opacity(appeared ? 1 : 0)

            // The lifted bubble
            bubble()
                .position(x: fromUser ? bubbleFrame.midX : bubbleFrame.midX, y: bubbleY)
                .scaleEffect(appeared ? 1 : 0.9, anchor: fromUser ? .trailing : .leading)

            // Action menu
            actionMenu
                .position(x: menuX, y: bubbleY + bubbleFrame.height / 2 + 12 + menuHeight / 2)
                .scaleEffect(appeared ? 1 : 0.8, anchor: fromUser ? .topTrailing : .topLeading)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.ggSnappy) { appeared = true }
        }
    }

    private var barX: CGFloat {
        let w: CGFloat = 300
        let half = w / 2 + 12
        return min(max(bubbleFrame.midX, half), UIScreen.main.bounds.width - half)
    }

    private var menuWidth: CGFloat { 230 }
    private var menuHeight: CGFloat { CGFloat(actions.count) * 48 }
    private var menuX: CGFloat {
        let half = menuWidth / 2 + 12
        let anchor = fromUser ? bubbleFrame.maxX - menuWidth / 2 : bubbleFrame.minX + menuWidth / 2
        return min(max(anchor, half), UIScreen.main.bounds.width - half)
    }

    private var tapbackBar: some View {
        HStack(spacing: 10) {
            ForEach(WorldTapback.allCases) { tb in
                Button {
                    onTapback(tb)
                } label: {
                    Image(systemName: tb.pickerSymbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(existingUserTapback == tb ? Color.white
                                         : (tb == .heart ? Color(red: 1, green: 0.4, blue: 0.5) : IMColor.label))
                        .frame(width: 38, height: 38)
                        .background(
                            Circle().fill(existingUserTapback == tb ? IMColor.blue : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(Capsule().fill(IMColor.chrome.opacity(0.75)))
                .overlay(Capsule().strokeBorder(IMColor.label.opacity(0.12), lineWidth: 0.5))
        )
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
    }

    private struct MenuAction: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let destructive: Bool
        let action: () -> Void
    }

    private var actions: [MenuAction] {
        [
            MenuAction(title: "Reply", icon: "arrowshape.turn.up.left", destructive: false, action: onReply),
            MenuAction(title: "Copy", icon: "doc.on.doc", destructive: false, action: onCopy),
            MenuAction(title: "Translate", icon: "character.bubble", destructive: false, action: onDismiss),
            MenuAction(title: "Delete", icon: "trash", destructive: true, action: onDelete),
        ]
    }

    private var actionMenu: some View {
        VStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { i, item in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    item.action()
                } label: {
                    HStack {
                        Text(item.title)
                            .font(.system(size: 17))
                            .foregroundStyle(item.destructive ? Color(red: 1, green: 0.27, blue: 0.23) : IMColor.label)
                        Spacer()
                        Image(systemName: item.icon)
                            .font(.system(size: 17))
                            .foregroundStyle(item.destructive ? Color(red: 1, green: 0.27, blue: 0.23) : IMColor.label)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < actions.count - 1 {
                    Divider().background(IMColor.label.opacity(0.08))
                }
            }
        }
        .frame(width: menuWidth)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(IMColor.chrome.opacity(0.9)))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
    }
}

// MARK: - Poll bubble

struct WorldPollBubble: View {
    let poll: WorldPoll
    let fromUser: Bool
    var onVote: (UUID) -> Void
    var onAddOption: (String) -> Void

    @State private var addingOption = false
    @State private var newOption = ""
    @FocusState private var addFocused: Bool

    private var total: Int { max(poll.totalVotes, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Poll")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle((fromUser ? Color.white : IMColor.label).opacity(0.75))

            Text(poll.question)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(fromUser ? Color.white : IMColor.label)

            VStack(spacing: 8) {
                ForEach(poll.options) { opt in
                    optionRow(opt)
                }
            }

            if addingOption {
                HStack(spacing: 8) {
                    TextField("New option", text: $newOption)
                        .font(.system(size: 15))
                        .foregroundStyle(fromUser ? Color.white : IMColor.label)
                        .focused($addFocused)
                        .onSubmit(commitOption)
                    Button(action: commitOption) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(fromUser ? Color.white : IMColor.blue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(bgTint.opacity(0.4)))
            } else {
                Button {
                    addingOption = true
                    addFocused = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                        Text("Add Choice")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle((fromUser ? Color.white : IMColor.blue).opacity(0.9))
                }
                .buttonStyle(.plain)
            }

            Text("\(poll.totalVotes) vote\(poll.totalVotes == 1 ? "" : "s")")
                .font(.system(size: 12))
                .foregroundStyle((fromUser ? Color.white : IMColor.secondary).opacity(0.7))
        }
        .padding(14)
        .frame(width: 250, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(fromUser ? IMColor.blue : IMColor.bubbleGray)
        )
    }

    private var bgTint: Color { fromUser ? Color.white : IMColor.label }

    private func optionRow(_ opt: WorldPollOption) -> some View {
        let picked = opt.voters.contains("You")
        let fraction = Double(opt.voters.count) / Double(total)
        return Button {
            onVote(opt.id)
        } label: {
            ZStack(alignment: .leading) {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(bgTint.opacity(0.18))
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(bgTint.opacity(0.32))
                        .frame(width: max(38, geo.size.width * fraction))
                        .animation(.ggNav, value: fraction)
                }
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .strokeBorder(bgTint.opacity(0.6), lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                        if picked {
                            Circle().fill(fromUser ? Color.white : IMColor.blue)
                                .frame(width: 20, height: 20)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(fromUser ? IMColor.blue : Color.white)
                        }
                    }
                    Text(opt.text)
                        .font(.system(size: 15, weight: picked ? .semibold : .regular))
                        .foregroundStyle(fromUser ? Color.white : IMColor.label)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if opt.voters.count > 0 {
                        Text("\(opt.voters.count)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle((fromUser ? Color.white : IMColor.label).opacity(0.8))
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 40)
        }
        .buttonStyle(.plain)
    }

    private func commitOption() {
        let t = newOption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { addingOption = false; return }
        onAddOption(t)
        newOption = ""
        addingOption = false
        addFocused = false
    }
}

// MARK: - Poll composer sheet

struct WorldPollComposer: View {
    var onSend: (String, [String]) -> Void
    var onCancel: () -> Void = {}

    @State private var question = ""
    @State private var options: [String] = ["", ""]
    @FocusState private var focusedField: Int?

    private var canSend: Bool {
        !question.trimmingCharacters(in: .whitespaces).isEmpty
            && options.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count >= 2
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    questionField
                    choicesSection
                }
                .padding(16)
            }
        }
        .background(IMColor.sheetBG)
        .onAppear { focusedField = -1 }
    }

    private var questionField: some View {
        field("QUESTION") {
            TextField("Ask something…", text: $question)
                .font(.system(size: 17))
                .foregroundStyle(IMColor.label)
                .focused($focusedField, equals: -1)
        }
    }

    private var choicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHOICES")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IMColor.secondary)
                .padding(.leading, 4)

            ForEach(options.indices, id: \.self) { i in
                choiceRow(i)
            }

            Button {
                withAnimation { options.append("") }
                focusedField = options.count - 1
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Choice")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(IMColor.blue)
                .padding(.vertical, 6)
                .padding(.leading, 4)
            }
            .buttonStyle(.plain)
        }
    }

    private func choiceRow(_ i: Int) -> some View {
        HStack(spacing: 10) {
            TextField("Choice \(i + 1)", text: $options[i])
                .font(.system(size: 17))
                .foregroundStyle(IMColor.label)
                .focused($focusedField, equals: i)
            if options.count > 2 {
                Button {
                    withAnimation { _ = options.remove(at: i) }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(IMColor.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(IMColor.chrome))
    }

    private var header: some View {
        ZStack {
            Text("New Poll")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(IMColor.label)
            HStack {
                Button("Cancel") { onCancel() }
                    .font(.system(size: 17))
                    .foregroundStyle(IMColor.blue)
                Spacer()
                Button {
                    onSend(question, options)
                } label: {
                    Text("Send")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(canSend ? IMColor.blue : IMColor.secondary)
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IMColor.secondary)
                .padding(.leading, 4)
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(IMColor.chrome))
        }
    }
}
