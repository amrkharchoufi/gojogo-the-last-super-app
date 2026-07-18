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

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    storyRail
                        .padding(.top, 4)
                        .padding(.bottom, 8)

                    ForEach(app.posts) { post in
                        InstagramPostCard(post: post)
                        Rectangle()
                            .fill(GGColor.ink(0.08))
                            .frame(height: 0.5)
                    }

                    Color.clear.frame(height: tabBarInset)
                }
                .padding(.top, 52)
            }
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
        .onChange(of: storyPicker) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    app.addStory(imageData: data)
                    storyPicker = nil
                }
            }
        }
    }

    // MARK: Stories — single horizontal rail

    private var storyRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(app.storyTray) { story in
                    storyCell(story)
                }
                moreStoryCell
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    private var moreStoryCell: some View {
        Button {
            app.showStoriesBrowser = true
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            GGColor.ink(0.28),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                        .frame(width: 90, height: 90)
                    Text("+")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(GGColor.ink(0.85))
                }
                Text("More")
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textSecondary)
                    .frame(width: 90)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func storyCell(_ story: Story) -> some View {
        let hasMedia = story.hasMedia
        let ring: Bool = story.isYou || (hasMedia && !story.seen)

        let label = VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                UserAvatar(
                    size: 84,
                    letter: story.letter,
                    ring: ring,
                    imageURL: story.isYou && !hasMedia ? app.user.avatarURL : story.imageURL,
                    imageData: story.imageData
                )
                .opacity(story.seen && !story.isYou ? 0.72 : 1)

                if story.isYou {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.black, .white)
                        .font(.system(size: 24))
                        .background(Circle().fill(.black).padding(2))
                        .offset(x: 2, y: 2)
                }
            }
            .frame(width: 90, height: 90)

            Text(story.isYou ? "Your story" : story.name)
                .font(.system(size: 11))
                .foregroundStyle(story.seen && !story.isYou ? GGColor.textTertiary : GGColor.textPrimary)
                .frame(width: 90)
                .lineLimit(1)
        }

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
    @State private var isInViewport = true

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

    private var shouldPlayVideo: Bool { isInViewport && !isHolding }

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
            .onDisappear {
                isInViewport = false
                isHolding = false
            }
        }
    }

    private func feedSlide(_ slide: PostMediaItem, index: Int) -> some View {
        ZStack {
            MediaImage(url: slide.imageURL, data: slide.imageData, cornerRadius: 0)
                .frame(maxWidth: .infinity)
                .frame(height: mediaHeight)
                .clipped()

            if slide.isVideo, let videoURL = slide.videoURL, !videoURL.isEmpty {
                // Only the active page attaches the shared player layer (avoids duplicates).
                if carouselPage == index {
                    ShortVideoPlayer(
                        urlString: videoURL,
                        isActive: shouldPlayVideo,
                        isMuted: app.feedVideosMuted
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: mediaHeight)
                    .clipped()
                    .allowsHitTesting(false)
                }
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
        .onTapGesture {
            guard slide.isVideo, !isHolding else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            app.openFeedVideoAsShort(postID: live.id)
        }
        .onLongPressGesture(
            minimumDuration: 0.22,
            maximumDistance: 40,
            pressing: { pressing in
                guard slide.isVideo else { return }
                // Release finger → resume. Pause only after hold fires in `perform`.
                if !pressing {
                    isHolding = false
                }
            },
            perform: {
                guard slide.isVideo else { return }
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

    func makeUIView(context: Context) -> FeedViewportUIView {
        let view = FeedViewportUIView()
        view.onVisibilityChange = { visible in
            if isVisible != visible {
                isVisible = visible
            }
        }
        return view
    }

    func updateUIView(_ uiView: FeedViewportUIView, context: Context) {
        uiView.onVisibilityChange = { visible in
            if isVisible != visible {
                isVisible = visible
            }
        }
        uiView.checkVisibility()
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
        checkVisibility()
    }

    deinit {
        displayLink?.invalidate()
    }
}

/// Kept as alias so older references keep compiling.
typealias FullPostCard = InstagramPostCard
