import SwiftUI
import PhotosUI
import UIKit

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var storyPicker: PhotosPickerItem?
    @State private var hideChrome = false

    var body: some View {
        ZStack(alignment: .top) {
            GGColor.bg.ignoresSafeArea()

            // A List (UITableView-backed) instead of ScrollView+LazyVStack: List keeps
            // the top visible row pinned when off-screen rows re-measure, so re-renders
            // from bottom-nav taps can't shift the feed. A LazyVStack, by contrast,
            // re-estimates heterogeneous off-screen row heights on every re-render and
            // jumps (a half-scrolled video would snap into view).
            List {
                Group {
                    storyRail
                        .padding(.top, 52 + 4)
                        .padding(.bottom, 8)

                    ForEach(app.posts) { post in
                        VStack(spacing: 0) {
                            InstagramPostCard(post: post)
                            Rectangle()
                                .fill(GGColor.ink(0.08))
                                .frame(height: 0.5)
                        }
                    }

                    Color.clear.frame(height: tabBarInset)
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .coordinateSpace(name: "homeFeed")
            .trackScrollChrome(hidden: $hideChrome)

            // Top chrome — Instagram: wordmark left, actions right
            HStack(spacing: 16) {
                Wordmark(size: 22)
                Spacer()
                ThemeToggleButton(size: 20)

                Button {
                    app.openActivity()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "heart")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(GGColor.textPrimary)
                        if app.unreadActivityCount > 0 {
                            Text("\(min(app.unreadActivityCount, 9))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .background(Circle().fill(Color(hex: "E85D75")))
                                .offset(x: 7, y: -5)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Activity")

                Button { app.openOwnProfile() } label: {
                    UserAvatar(
                        size: 28,
                        gradient: app.user.avatarGradient,
                        letter: String(app.user.name.prefix(1)),
                        imageURL: app.user.avatarURL
                    )
                    .overlay(Circle().strokeBorder(GGColor.ink(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile")
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .background(
                LinearGradient(
                    colors: [GGColor.bg.opacity(0.96), GGColor.bg.opacity(0.72), GGColor.bg.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            )
            .autoHideChrome(hideChrome)
        }
        // Keep feed scroll geometry out of tab-bar spring animations.
        .animation(nil, value: app.navBarExpanded)
        .onChange(of: app.navBarExpanded) { _, _ in
            ScrollChromeControl.suppressTabBarJitter()
            hideChrome = false
        }
        .onChange(of: app.activeTab) { _, _ in
            ScrollChromeControl.suppressTabBarJitter()
            hideChrome = false
        }
        .onChange(of: storyPicker) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    app.addStory(imageData: data)
                    storyPicker = nil
                }
            }
        }
    }

    // MARK: Stories — 3×3 circle grid (Messages Favorites style)

    private let storyCircleSize: CGFloat = 80
    private let storyColGap: CGFloat = 18

    /// First 8 tray stories + More as the 9th cell.
    private var homeStorySlots: [Story] {
        Array(app.storyTray.prefix(8))
    }

    /// Total cells = stories + the trailing "More" cell.
    private var storyCellCount: Int { homeStorySlots.count + 1 }

    /// Row start indices for a fixed 3-column layout.
    private var storyRowStarts: [Int] {
        Array(stride(from: 0, to: storyCellCount, by: 3))
    }

    // A non-lazy grid: the rail is a small, fixed set of cells (≤9), so laziness
    // buys nothing and actively hurts — a nested LazyVGrid reports a different
    // height once it scrolls off-screen above the feed, and any re-render (e.g. a
    // bottom-nav tap) re-resolves that height and jumps the whole feed. A plain
    // VStack/HStack keeps a stable, deterministic height at all scroll positions.
    private var storyRail: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                ForEach(storyRowStarts, id: \.self) { start in
                    HStack(spacing: storyColGap) {
                        ForEach(start..<min(start + 3, storyCellCount), id: \.self) { i in
                            storyRailCell(i)
                        }
                        // Pad short final rows so columns stay left-anchored.
                        ForEach(0..<max(0, start + 3 - storyCellCount), id: \.self) { _ in
                            Color.clear.frame(width: storyCircleSize, height: 1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func storyRailCell(_ i: Int) -> some View {
        if i < homeStorySlots.count {
            storyCell(homeStorySlots[i])
        } else {
            moreStoryCell
        }
    }

    private var moreStoryCell: some View {
        Button {
            app.showStoriesBrowser = true
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            GGColor.ink(0.28),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                        .frame(width: storyCircleSize, height: storyCircleSize)
                    Text("+")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(GGColor.ink(0.85))
                }

                Text("More")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GGColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: storyCircleSize)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func storyCell(_ story: Story) -> some View {
        let hasMedia = story.hasMedia
        let ring: Bool = story.isYou || (hasMedia && !story.seen)

        let label = VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                UserAvatar(
                    size: storyCircleSize,
                    letter: story.letter,
                    ring: ring,
                    imageURL: story.isYou && !hasMedia ? app.user.avatarURL : story.imageURL,
                    imageData: story.imageData
                )
                .opacity(story.seen && !story.isYou ? 0.72 : 1)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

                if story.isYou {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.black, .white)
                        .font(.system(size: 18))
                        .background(Circle().fill(.black).padding(2))
                        .offset(x: 1, y: 1)
                }
            }

            Text(story.isYou ? "Your story" : story.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(story.seen && !story.isYou ? GGColor.textTertiary : GGColor.textSecondary)
                .lineLimit(1)
        }
        .frame(width: storyCircleSize)

        if story.isYou && !hasMedia {
            PhotosPicker(selection: $storyPicker, matching: .images) { label }
        } else if hasMedia {
            Button { app.openStory(story) } label: { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }
}

// MARK: - Instagram-style post

struct InstagramPostCard: View {
    @EnvironmentObject var app: AppState
    let post: Post
    @State private var heartTrigger = 0
    @State private var isHolding = false
    @State private var carouselPage = 0
    /// Drives autoplay / stop when scrolling the feed.
    /// Start false — otherwise every recycled cell autoplays until the observer runs.
    @State private var isInViewport = false

    private var live: Post {
        app.posts.first(where: { $0.id == post.id }) ?? post
    }

    private var slides: [PostMediaItem] { live.carouselSlides }

    private var mediaHeight: CGFloat {
        // Instagram portrait feed (~4:5 — taller than square).
        let aspect = live.imageAspect > 0 ? live.imageAspect : 1.25
        let clamped = min(max(aspect, 1.15), 1.4)
        return UIScreen.main.bounds.width * clamped
    }

    /// Only the feed's focused post may play — prevents stacked carousel / neighbor audio.
    private var shouldPlayVideo: Bool {
        isInViewport && !isHolding && app.activeFeedVideoPostID == live.id
    }

    var body: some View {
        let card = VStack(alignment: .leading, spacing: 0) {
            header
            captionBlock
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            media
            PostActions(post: live) {
                heartTrigger += 1
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .frame(minHeight: 52)

            timestamp
                .padding(.horizontal, 14)
                .padding(.bottom, 18)
        }
        .padding(.bottom, 6)

        // Context menu long-press fights hold-to-pause on feed videos.
        if live.isVideo && !live.isCarousel {
            card
        } else {
            card
                .contextMenu {
                    postContextMenu
                } preview: {
                    postContextPreview
                }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                app.openUserProfile(
                    handle: live.author,
                    avatarURL: live.avatarURL,
                    avatarGradient: live.avatarGradient
                )
            } label: {
                HStack(spacing: 12) {
                    UserAvatar(
                        size: 40,
                        gradient: live.avatarGradient,
                        letter: String(live.author.prefix(1)).uppercased(),
                        imageURL: live.avatarURL
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(live.author)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                        if !live.meta.isEmpty {
                            Text(live.meta)
                                .font(.system(size: 13))
                                .foregroundStyle(GGColor.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            if live.showFollow {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { app.toggleFollow(postID: live.id) }
                } label: {
                    Text(live.following ? "Following" : "Follow")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(live.following ? GGColor.textSecondary : .white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(live.following ? GGColor.ink(0.08) : GGColor.ink(0.16))
                        )
                }
                .buttonStyle(.plain)
            }

            Menu {
                postContextMenu
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(minHeight: 64)
    }

    @ViewBuilder
    private var media: some View {
        if !slides.isEmpty {
            let activeSlide = slides[min(carouselPage, slides.count - 1)]
            let activeIsVideo = activeSlide.isVideo && !(activeSlide.videoURL?.isEmpty ?? true)

            ZStack(alignment: .topTrailing) {
                Group {
                    if slides.count == 1 {
                        feedSlide(slides[0], index: 0)
                    } else {
                        TabView(selection: $carouselPage) {
                            ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                                feedSlide(slide, index: index)
                                    .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .clipped()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: mediaHeight)

                HeartBurstOverlay(trigger: heartTrigger)
                    .allowsHitTesting(false)

                if slides.count > 1 {
                    Text("\(carouselPage + 1)/\(slides.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .padding(12)
                }

                if slides.count > 1 {
                    HStack(spacing: 5) {
                        ForEach(0..<slides.count, id: \.self) { i in
                            Circle()
                                .fill(i == carouselPage ? Color.white : Color.white.opacity(0.4))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 12)
                    .allowsHitTesting(false)
                }

                if activeIsVideo && isHolding {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(16)
                        .background(Circle().fill(Color.black.opacity(0.4)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }

                if activeIsVideo {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        app.toggleFeedVideoMute()
                    } label: {
                        Image(systemName: app.feedVideosMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
                }
            }
            .frame(height: mediaHeight)
            .clipped()
            .background {
                FeedViewportObserver(isVisible: $isInViewport)
            }
            .onChange(of: isInViewport) { _, visible in
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    if visible {
                        app.activeFeedVideoPostID = live.id
                    } else if app.activeFeedVideoPostID == live.id {
                        app.activeFeedVideoPostID = nil
                    }
                }
            }
            .onChange(of: carouselPage) { _, _ in
                // Drop hold-pause when switching slides; only the new page may play.
                isHolding = false
                if isInViewport {
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        app.activeFeedVideoPostID = live.id
                    }
                }
            }
            .onDisappear {
                isInViewport = false
                isHolding = false
                if app.activeFeedVideoPostID == live.id {
                    app.activeFeedVideoPostID = nil
                }
            }
        }
    }

    private func feedSlide(_ slide: PostMediaItem, index: Int) -> some View {
        let isVideoSlide = slide.isVideo && !(slide.videoURL?.isEmpty ?? true)
        // Keep current ±1 players mounted so swipe doesn't flash a poster.
        let keepPlayerMounted = abs(carouselPage - index) <= 1

        return ZStack {
            Color.black

            if isVideoSlide, let videoURL = slide.videoURL, keepPlayerMounted {
                ShortVideoPlayer(
                    urlString: videoURL,
                    isActive: shouldPlayVideo && carouselPage == index,
                    isMuted: app.feedVideosMuted
                )
                .frame(maxWidth: .infinity)
                .frame(height: mediaHeight)
                .clipped()
                .allowsHitTesting(false)
            } else if !isVideoSlide {
                MediaImage(url: slide.imageURL, data: slide.imageData, cornerRadius: 0)
                    .frame(maxWidth: .infinity)
                    .frame(height: mediaHeight)
                    .clipped()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: mediaHeight)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            _ = app.likePost(live.id)
            heartTrigger += 1
        }
        .onLongPressGesture(
            minimumDuration: 0.22,
            maximumDistance: 40,
            pressing: { pressing in
                guard isVideoSlide else { return }
                // Release finger → resume. Pause only after hold fires in `perform`.
                if !pressing {
                    isHolding = false
                }
            },
            perform: {
                guard isVideoSlide else { return }
                isHolding = true
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        )
    }

    @ViewBuilder
    private var captionBlock: some View {
        if let text = live.text, !text.isEmpty {
            (Text(live.author).fontWeight(.semibold) + Text(" ") + Text(text))
                .font(.system(size: 15))
                .foregroundStyle(GGColor.textPrimary)
                .lineSpacing(3)
                .lineLimit(3)
        } else if live.likeCount > 0 {
            Text("\(formatCount(live.likeCount)) likes")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
        }
    }

    private var timestamp: some View {
        Text(live.meta.isEmpty ? "just now" : live.meta)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(GGColor.textTertiary)
    }

    @ViewBuilder
    private var postContextMenu: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                app.toggleLike(live.id)
            }
        } label: {
            Label(live.liked ? "Unlike" : "Like",
                  systemImage: live.liked ? "heart.slash" : "heart")
        }

        Button {
            app.openComments(for: live.id)
        } label: {
            Label("Comment", systemImage: "bubble.right")
        }

        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                app.toggleBookmark(live.id)
            }
        } label: {
            Label(live.bookmarked ? "Unsave" : "Save",
                  systemImage: live.bookmarked ? "bookmark.slash" : "bookmark")
        }

        if live.showFollow {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    app.toggleFollow(postID: live.id)
                }
            } label: {
                Label(live.following ? "Unfollow" : "Follow \(live.author)",
                      systemImage: live.following ? "person.badge.minus" : "person.badge.plus")
            }
        }

        Divider()

        ShareLink(
            item: app.postShareURL(for: live.id),
            subject: Text(live.author),
            message: Text(live.text ?? "Post by \(live.author) on gojogo")
        ) {
            Label("Share", systemImage: "square.and.arrow.up")
        }

        Button {
            UIPasteboard.general.string = app.postShareURL(for: live.id).absoluteString
        } label: {
            Label("Copy Link", systemImage: "link")
        }

        Divider()

        Button(role: .destructive) {
            withAnimation(.easeInOut(duration: 0.25)) {
                app.hidePost(live.id)
            }
        } label: {
            Label("Hide", systemImage: "eye.slash")
        }

        Button(role: .destructive) {
            withAnimation(.easeInOut(duration: 0.25)) {
                app.hidePost(live.id)
            }
        } label: {
            Label("Report", systemImage: "flag")
        }
    }

    private var postContextPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                UserAvatar(size: 28, gradient: live.avatarGradient,
                           letter: String(live.author.prefix(1)).uppercased(),
                           imageURL: live.avatarURL)
                Text(live.author)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Spacer(minLength: 0)
            }

            if live.imageURL != nil || live.imageData != nil {
                MediaImage(url: live.imageURL, data: live.imageData, cornerRadius: 12)
                    .frame(width: 260, height: 180)
                    .clipped()
            }

            if let text = live.text {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(GGColor.textPrimary.opacity(0.9))
                    .lineLimit(4)
                    .frame(maxWidth: 260, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: 288)
        .background(GGColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Reports whether the feed media is meaningfully on-screen (UIKit — reliable while scrolling).
private struct FeedViewportObserver: UIViewRepresentable {
    @Binding var isVisible: Bool

    func makeCoordinator() -> Coordinator { Coordinator(isVisible: $isVisible) }

    func makeUIView(context: Context) -> FeedViewportUIView {
        let view = FeedViewportUIView()
        view.onVisibilityChange = { visible in
            context.coordinator.apply(visible)
        }
        return view
    }

    func updateUIView(_ uiView: FeedViewportUIView, context: Context) {
        context.coordinator.isVisible = $isVisible
        uiView.onVisibilityChange = { visible in
            context.coordinator.apply(visible)
        }
        // Do not checkVisibility() here — SwiftUI updates (tab bar morph)
        // would flicker play/pause and spring the feed.
    }

    final class Coordinator {
        var isVisible: Binding<Bool>
        init(isVisible: Binding<Bool>) { self.isVisible = isVisible }

        func apply(_ visible: Bool) {
            guard isVisible.wrappedValue != visible else { return }
            if FeedViewportGate.shared.isSuppressed { return }
            DispatchQueue.main.async {
                guard self.isVisible.wrappedValue != visible else { return }
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    self.isVisible.wrappedValue = visible
                }
            }
        }
    }
}

final class FeedViewportGate {
    static let shared = FeedViewportGate()
    private var suppressUntil: Date = .distantPast
    private let lock = NSLock()

    var isSuppressed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return Date() < suppressUntil
    }

    func suppress(for seconds: TimeInterval = 0.5) {
        lock.lock()
        suppressUntil = Date().addingTimeInterval(seconds)
        lock.unlock()
    }
}

private final class FeedViewportUIView: UIView {
    var onVisibilityChange: ((Bool) -> Void)?
    private var displayLink: CADisplayLink?
    private var lastVisible: Bool?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startMonitoring()
            checkVisibility()
        } else {
            stopMonitoring()
            report(false)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Skip layout-driven checks while the tab bar is morphing.
        guard !FeedViewportGate.shared.isSuppressed else { return }
        checkVisibility()
    }

    func checkVisibility() {
        guard let window else {
            report(false)
            return
        }
        let frame = convert(bounds, to: window)
        guard bounds.width > 1, bounds.height > 1 else { return }

        let visibleBounds = window.bounds.insetBy(dx: 0, dy: window.bounds.height * 0.06)
        let overlap = frame.intersection(visibleBounds).height
        let ratio = overlap / max(frame.height, 1)
        // Hysteresis so tiny scroll jitter doesn't flicker play/pause.
        let currently = lastVisible ?? false
        let visible = currently ? ratio > 0.2 : ratio > 0.35
        report(visible)
    }

    private func report(_ visible: Bool) {
        guard lastVisible != visible else { return }
        lastVisible = visible
        onVisibilityChange?(visible)
    }

    private func startMonitoring() {
        stopMonitoring()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 15)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopMonitoring() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        guard !FeedViewportGate.shared.isSuppressed else { return }
        checkVisibility()
    }

    deinit {
        displayLink?.invalidate()
    }
}

/// Kept as alias so older references keep compiling.
typealias FullPostCard = InstagramPostCard
