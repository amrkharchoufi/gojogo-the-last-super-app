import SwiftUI
import UIKit

/// Instagram-style story viewer — multi-frame per person, tap + swipe +
/// hold-to-pause, photo / video / text cards, and the engagement bar
/// (reactions and replies going out, viewers coming back).
struct StoryViewer: View {
    @EnvironmentObject var app: AppState

    @State private var segmentProgress: CGFloat = 0
    @State private var videoProgress: Double = 0
    @State private var isPaused = false
    @State private var dragOffset: CGFloat = 0
    @State private var dragY: CGFloat = 0
    @State private var tick: Timer?
    @State private var generation = 0
    @State private var isDismissing = false
    @State private var isMuted = false
    @State private var replyText = ""
    @State private var showViewers = false
    @State private var showReplies = false
    @State private var showHighlightPicker = false
    @State private var confirmDelete = false
    @State private var showActions = false
    @State private var flyingReaction: String?
    /// The whole viewer ignores the safe area (media is full-bleed), so the
    /// keyboard can't push the reply bar up on its own — track it and lift.
    @State private var keyboardHeight: CGFloat = 0

    @FocusState private var replyFocused: Bool
    @StateObject private var musicController = StoryMusicController()

    private let tickInterval: Double = 1.0 / 60.0

    private var story: Story? {
        guard let id = app.viewingStory?.id else { return nil }
        return app.liveStory(id: id) ?? app.viewingStory
    }

    private var frameIndex: Int {
        guard let story else { return 0 }
        return min(max(app.viewingFrameIndex, 0), max(story.frames.count - 1, 0))
    }

    private var frame: StoryFrame? {
        guard let story, story.frames.indices.contains(frameIndex) else { return nil }
        return story.frames[frameIndex]
    }

    private var isOwn: Bool { story?.isYou == true }
    private var isHighlight: Bool { app.viewingHighlightTitle != nil }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // Overlay / covers can report 0 — fall back to window inset.
            let topInset = max(geo.safeAreaInsets.top, Self.windowTopInset, 47)
            let bottomInset = max(geo.safeAreaInsets.bottom, 8)
            ZStack {
                // Fixed backdrop — must NOT slide with the dismiss drag,
                // or Home peeks through and feels like a second page.
                Color.black.ignoresSafeArea()

                storyContent(width: w, topInset: topInset, bottomInset: bottomInset)
                    .offset(x: dragOffset, y: max(0, dragY))
                    .scaleEffect(1 - min(0.05, max(0, dragY) / 1600))
            }
            .highPriorityGesture(storyDrag(width: w, height: geo.size.height), including: gestureMask)
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(true)
        .onAppear { restartSegment() }
        .onChange(of: app.viewingStory?.id) { _, _ in restartSegment() }
        .onChange(of: app.viewingFrameIndex) { _, _ in restartSegment() }
        .onChange(of: replyFocused) { _, focused in
            withAnimation(.easeOut(duration: 0.2)) { setPaused(focused) }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                  let screen = UIApplication.shared.connectedScenes
                    .compactMap({ ($0 as? UIWindowScene)?.screen.bounds.height }).first
            else { return }
            keyboardHeight = max(0, screen - end.origin.y)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .onDisappear {
            stopTick()
            musicController.teardown()
        }
        .sheet(isPresented: $showViewers, onDismiss: { setPaused(false) }) {
            StoryInsightsSheet(frameID: frame?.id)
                .environmentObject(app)
        }
        .sheet(isPresented: $showReplies, onDismiss: { setPaused(false) }) {
            StoryInsightsSheet(frameID: frame?.id, repliesOnly: true)
                .environmentObject(app)
        }
        .sheet(isPresented: $showHighlightPicker, onDismiss: { setPaused(false) }) {
            if let frame {
                StoryHighlightPickerSheet(frameIDs: [frame.id])
                    .environmentObject(app)
            }
        }
        .confirmationDialog("Delete this story?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let story, let frame {
                    app.deleteStoryFrame(storyID: story.id, frameID: frame.id)
                }
            }
            Button("Cancel", role: .cancel) { setPaused(false) }
        } message: {
            Text("It will be removed for everyone. Highlights that include it lose it too.")
        }
    }

    /// While the reply field has focus the drag gesture would fight the
    /// keyboard's own dismiss — hand the screen over to the field.
    private var gestureMask: GestureMask {
        replyFocused ? .subviews : .all
    }

    private static var windowTopInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first?.windows.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        return window?.safeAreaInsets.top ?? 0
    }

    private func storyContent(width: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        ZStack {
            if let frame {
                StoryFrameCanvas(
                    frame: frame,
                    isActive: true,
                    isPaused: isPaused,
                    isMuted: isMuted,
                    videoProgress: $videoProgress,
                    onVideoFinished: { advanceFromPlayback() },
                    // Clear the reply bar / owner chips at the bottom.
                    musicStickerBottomInset: bottomInset + (isOwn ? 62 : 118))
                .ignoresSafeArea()
                .id(frame.id)
            }

            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.black.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: topInset + 120)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            tapZones(width: width)

            VStack(spacing: 12) {
                progressBars(width: max(width - 28, 0))
                    .padding(.horizontal, 14)

                header
                    .padding(.horizontal, 14)

                if isPaused && !replyFocused {
                    Text("Paused")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassCapsule(interactive: false)
                        .transition(.opacity.combined(with: .scale(0.95)))
                }

                Spacer()
            }
            .padding(.top, topInset + 6)
            .animation(.easeOut(duration: 0.15), value: isPaused)

            // Typing dims the story so the field and what you've written stay
            // readable over a bright frame.
            if replyFocused {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { replyFocused = false }
            }

            VStack(spacing: 0) {
                Spacer()
                bottomBar
                    .padding(.horizontal, 14)
                    .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 10 : bottomInset)
            }
            .animation(.easeOut(duration: 0.22), value: keyboardHeight)

            if let flyingReaction {
                Text(flyingReaction)
                    .font(.system(size: 64))
                    .transition(.scale(0.4).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
    }

    private func tapZones(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { retreat() }
                .frame(width: width * 0.3)

            Color.clear
                .contentShape(Rectangle())
                .onLongPressGesture(
                    minimumDuration: 0.12,
                    maximumDistance: 80,
                    pressing: { if !replyFocused { setPaused($0) } },
                    perform: {}
                )
                .onTapGesture { if replyFocused { replyFocused = false } else { advance() } }
                .frame(maxWidth: .infinity)

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { advance() }
                .frame(width: width * 0.3)
        }
        .ignoresSafeArea()
    }

    // MARK: Progress bars — only the active segment animates

    private func progressBars(width: CGFloat) -> some View {
        let count = max(story?.frames.count ?? 1, 1)
        let spacing: CGFloat = 4
        let barW = (width - spacing * CGFloat(count - 1)) / CGFloat(count)

        return HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { i in
                GeometryReader { barGeo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.28))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: barGeo.size.width * fillAmount(for: i))
                    }
                }
                .frame(width: max(barW, 1), height: 3)
            }
        }
        .transaction { $0.animation = nil }
    }

    private func fillAmount(for index: Int) -> CGFloat {
        if index < frameIndex { return 1 }
        if index > frameIndex { return 0 }
        // A video's bar follows real playback, not a parallel timer that would
        // drift away from it on a slow network.
        if frame?.kind == .video { return min(max(CGFloat(videoProgress), 0), 1) }
        return min(max(segmentProgress, 0), 1)
    }

    private var header: some View {
        HStack(spacing: 10) {
            UserAvatar(
                size: 34,
                letter: (story?.isYou ?? false) ? app.ownAvatarLetter : (story?.letter ?? "·"),
                ring: true,
                imageURL: headerAvatarURL,
                imageData: story?.imageData
            )
            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(app.viewingHighlightTitle ?? story?.name ?? "")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 6, y: 1)

                    if frame?.audience == .closeFriends {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(4)
                            .background(Circle().fill(Color.white.opacity(0.18)))
                    }
                }
                if let posted = postedLabel {
                    Text(posted)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Spacer()

            // One control for whatever this frame makes noise with.
            if frame?.kind == .video || frame?.music != nil {
                circleButton(isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                    isMuted.toggle()
                    musicController.setMuted(isMuted)
                }
            }

            menuButton

            circleButton("xmark") { dismissViewer() }
        }
    }

    private var headerAvatarURL: String? {
        if isHighlight { return story?.avatarURL }
        return isOwn ? app.user.avatarURL : (story?.avatarURL ?? story?.imageURL)
    }

    private var postedLabel: String? {
        guard !isHighlight, let created = frame?.createdAt else { return nil }
        let seconds = max(0, Date().timeIntervalSince(created))
        return switch seconds {
        case ..<60: "now"
        case ..<3600: "\(Int(seconds / 60))m ago"
        default: "\(Int(seconds / 3600))h ago"
        }
    }

    /// A plain button + dialog rather than a `Menu`: a `Menu` gives no hook to
    /// pause on open, and the story would keep advancing behind the open menu.
    private var menuButton: some View {
        Button {
            setPaused(true)
            showActions = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.black.opacity(0.35)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        }
        .confirmationDialog("", isPresented: $showActions) {
            if isOwn {
                Button("Add to highlight") { showHighlightPicker = true }
                Button("Who viewed this") { showViewers = true }
                if !isHighlight {
                    Button("Delete story", role: .destructive) { confirmDelete = true }
                }
            } else if let story {
                Button(story.muted ? "Unmute \(story.name)" : "Mute \(story.name)") {
                    app.toggleStoryMute(authorID: story.id)
                    dismissViewer()
                }
                // A story expires in 24 hours, which is exactly why reporting
                // one has to be reachable while it is on screen (2e M5). The
                // viewer is dismissed first: the report sheet cannot present
                // over a full-screen overlay that is still advancing.
                if let frame, StoriesStore.shared.isLive(frame.id) {
                    Button("Report", role: .destructive) {
                        let name = story.name
                        dismissViewer()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            app.openReport(.story, id: frame.id, label: "\(name)'s story")
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) { setPaused(false) }
        }
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.black.opacity(0.35)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        }
    }

    // MARK: Bottom bar — insights on your own story, engagement on everyone else's

    @ViewBuilder
    private var bottomBar: some View {
        if isOwn && !isHighlight {
            ownerBar
        } else if !isOwn, let frame, StoriesStore.shared.isLive(frame.id) {
            viewerBar(frame: frame)
        }
    }

    private var ownerBar: some View {
        HStack(spacing: 10) {
            Button {
                setPaused(true)
                showViewers = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "eye.fill").font(.system(size: 12, weight: .semibold))
                    Text(viewerCountLabel)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassCapsule(interactive: true)
            }

            if let replies = frame?.replyCount, replies > 0 {
                Button {
                    setPaused(true)
                    showReplies = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "bubble.left.fill").font(.system(size: 12, weight: .semibold))
                        Text("\(replies)").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassCapsule(interactive: true)
                }
            }

            Spacer()
        }
    }

    private var viewerCountLabel: String {
        let count = frame?.viewerCount ?? 0
        return count == 1 ? "1 view" : "\(count) views"
    }

    private func viewerBar(frame: StoryFrame) -> some View {
        VStack(spacing: 10) {
            if !replyFocused {
                HStack(spacing: 10) {
                    ForEach(StoryReactions.quick, id: \.self) { emoji in
                        Button {
                            react(emoji, on: frame)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 26))
                                .scaleEffect(frame.myReaction == emoji ? 1.25 : 1)
                                .padding(3)
                        }
                    }
                }
                .animation(.ggPop, value: frame.myReaction)
                .transition(.opacity)
            }

            HStack(spacing: 10) {
                TextField("Send a reply…", text: $replyText, axis: .vertical)
                    .focused($replyFocused)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .lineLimit(1...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .glassCapsule(interactive: true)

                if !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        sendReply(to: frame)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(GGColor.onAccent)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(GGColor.accent))
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.ggSnappy, value: replyText.isEmpty)
        }
        .animation(.ggSnappy, value: replyFocused)
    }

    // MARK: Engagement actions

    private func react(_ emoji: String, on frame: StoryFrame) {
        guard let story else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let wasSet = frame.myReaction == emoji
        app.reactToStoryFrame(storyID: story.id, frameID: frame.id, emoji: emoji)
        guard !wasSet else { return }
        withAnimation(.ggPop) { flyingReaction = emoji }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.25)) { flyingReaction = nil }
        }
    }

    private func sendReply(to frame: StoryFrame) {
        let text = replyText
        replyText = ""
        replyFocused = false
        Task {
            if await app.replyToStoryFrame(frameID: frame.id, text: text) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                app.showStoryNotice("Reply sent")
            } else {
                replyText = text
            }
        }
    }

    // MARK: Gestures

    private func storyDrag(width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard !isDismissing, !replyFocused else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                if !isPaused { setPaused(true) }

                if abs(dy) > abs(dx) * 1.05 {
                    // Vertical — swipe down to dismiss (content only)
                    dragY = max(0, dy)
                    dragOffset = 0
                } else {
                    dragOffset = dx * 0.9
                    dragY = 0
                }
            }
            .onEnded { value in
                guard !isDismissing, !replyFocused else { return }
                let dx = value.predictedEndTranslation.width
                let dy = value.predictedEndTranslation.height
                let hThreshold = width * 0.22
                let vThreshold: CGFloat = 110

                if abs(value.translation.height) > abs(value.translation.width),
                   max(value.translation.height, dy) > vThreshold {
                    // Instant close — no second-page slide/fight with presentation.
                    dismissViewer()
                    return
                }

                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                    if dx < -hThreshold {
                        dragOffset = -width
                    } else if dx > hThreshold {
                        dragOffset = width
                    } else {
                        dragOffset = 0
                        dragY = 0
                    }
                }

                if dx < -hThreshold {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                        dragOffset = 0
                        dragY = 0
                        app.jumpToAdjacentAuthor(forward: true)
                        setPaused(false)
                    }
                } else if dx > hThreshold {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                        dragOffset = 0
                        dragY = 0
                        app.jumpToAdjacentAuthor(forward: false)
                        setPaused(false)
                    }
                } else {
                    setPaused(false)
                }
            }
    }

    private func dismissViewer() {
        guard !isDismissing else { return }
        isDismissing = true
        stopTick()
        musicController.teardown()
        replyFocused = false
        dragY = 0
        dragOffset = 0
        app.closeStoryViewer()
        isDismissing = false
    }

    private func advance() {
        guard !isDismissing else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        stopTick()
        _ = app.advanceStory()
    }

    /// A video reaching its end advances without the tap haptic.
    private func advanceFromPlayback() {
        guard !isDismissing, !isPaused else { return }
        stopTick()
        _ = app.advanceStory()
    }

    private func retreat() {
        guard !isDismissing else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        stopTick()
        _ = app.retreatStory()
    }

    private func setPaused(_ paused: Bool) {
        guard isPaused != paused else { return }
        isPaused = paused
        musicController.setPaused(paused)
        if paused {
            stopTick(keepProgress: true)
        } else if frame?.kind != .video {
            startTick()
        }
    }

    // MARK: Timer-driven progress (stills and text cards only)

    private func restartSegment() {
        guard let story, let frame else { return }
        app.markFrameSeen(storyID: story.id, frameID: frame.id)
        app.loadInsightsForCurrentFrame()
        generation += 1
        segmentProgress = 0
        videoProgress = 0
        isPaused = false
        replyText = ""
        // The sound belongs to the frame, so it restarts with it rather than
        // bleeding across a swipe.
        if let music = frame.music {
            musicController.play(music, muted: isMuted)
        } else {
            musicController.teardown()
        }
        // Video drives its own progress and its own end — no timer for it.
        if frame.kind != .video {
            startTick()
        } else {
            stopTick()
        }
    }

    private func startTick() {
        stopTick(keepProgress: true)
        let gen = generation
        let duration = frame?.displayDuration ?? 5
        let step = CGFloat(tickInterval / max(duration, 0.5))
        let timer = Timer(timeInterval: tickInterval, repeats: true) { timer in
            DispatchQueue.main.async {
                guard gen == self.generation, !self.isPaused, !self.isDismissing else { return }
                self.segmentProgress = min(1, self.segmentProgress + step)
                if self.segmentProgress >= 1 {
                    timer.invalidate()
                    if self.tick === timer { self.tick = nil }
                    _ = self.app.advanceStory()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    private func stopTick(keepProgress: Bool = false) {
        tick?.invalidate()
        tick = nil
        _ = keepProgress
    }
}
