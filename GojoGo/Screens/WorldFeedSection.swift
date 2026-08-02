import SwiftUI

// MARK: - GojoMessages feed (Phase 2f)
//
// The home screen the re-spec asks for: a stories row, then posts from people
// whose number you have, and the messages list underneath (owned by
// MyWorldView, which renders this above it).
//
// Every name here goes through `app.worldAuthorName` — the wire carries the name
// the author set, and the viewer's private rename is applied on top.

struct WorldFeedSection: View {
    @EnvironmentObject var app: AppState

    /// The first fetch hasn't landed, so the row and the card stand in for what
    /// is coming. Read once per body rather than per subview, so the stories and
    /// the posts can't disagree about whether the feed is still loading.
    private var loading: Bool { app.shouldShowWorldFeedShimmer }

    var body: some View {
        VStack(spacing: 0) {
            if loading || !app.worldStories.isEmpty || app.worldSetupComplete {
                storiesRow
            }
            if loading {
                postsShimmerRow
                sectionDivider("Messages")
            } else if !app.worldFeedPosts.isEmpty {
                postsRow
                sectionDivider("Messages")
            }
        }
    }

    // MARK: Loading

    /// One card's worth of placeholder, sized like the real thing so the feed
    /// doesn't jump when the posts arrive.
    private var postsShimmerRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(IMColor.chrome)
                    .frame(width: 34, height: 34)
                    .shimmering()
                VStack(alignment: .leading, spacing: 6) {
                    Capsule()
                        .fill(IMColor.chrome)
                        .frame(width: 120, height: 11)
                        .shimmering()
                    Capsule()
                        .fill(IMColor.chrome)
                        .frame(width: 54, height: 9)
                        .shimmering()
                }
                Spacer(minLength: 0)
            }
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(IMColor.chrome)
                .frame(height: 210)
                .shimmering()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(IMColor.inputFill))
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .allowsHitTesting(false)
        .accessibilityLabel("Loading posts")
    }

    private var storyShimmerBubble: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(IMColor.chrome)
                .frame(width: 62, height: 62)
                .shimmering()
            Capsule()
                .fill(IMColor.chrome)
                .frame(width: 42, height: 9)
                .shimmering()
        }
        .frame(width: 70)
        .allowsHitTesting(false)
    }

    // MARK: Posts

    /// Posts swipe sideways rather than stacking, so the feed costs one screen
    /// of height however many there are and the messages list stays in reach.
    ///
    /// Cards are sized against the scroll view rather than a fixed width so they
    /// keep the same inset on every device, and snap one at a time.
    private var postsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(app.worldFeedPosts) { post in
                    WorldPostCard(post: post, pagedHorizontally: true)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        // The inset lives on the scroll view, not inside it: that way a card is
        // measured against the *visible* width, so it lands on the same margin
        // it started from when the swipe settles.
        .safeAreaPadding(.horizontal, 16)
        .scrollTargetBehavior(.viewAligned)
        .padding(.bottom, 14)
    }

    // MARK: Stories

    /// Your own ring, pulled out of the row so it renders as "Your story"
    /// rather than as one more contact. The server merges your own content into
    /// your feed, so posting a story is visible to you immediately.
    private var myRing: WorldStoryRing? {
        guard let me = SocialStore.shared.myProfileId else { return nil }
        return app.worldStories.first { $0.authorID == me }
    }

    private var otherRings: [WorldStoryRing] {
        guard let me = SocialStore.shared.myProfileId else { return app.worldStories }
        return app.worldStories.filter { $0.authorID != me }
    }

    private var storiesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                yourStoryBubble
                // Your own bubble is real from the first frame — it's yours, and
                // it composes. The rings beside it are what the fetch is for.
                if loading {
                    ForEach(0..<4, id: \.self) { _ in storyShimmerBubble }
                }
                ForEach(otherRings) { ring in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        app.openWorldStory = ring
                    } label: {
                        storyBubble(ring)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    /// Tapping opens your own story when you have one, and the composer when you
    /// don't. The `+` badge always composes, so posting a second frame stays one
    /// tap away once the bubble has become a ring.
    private var yourStoryBubble: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if let myRing {
                        app.openWorldStory = myRing
                    } else {
                        compose()
                    }
                } label: {
                    if let myRing {
                        ZStack {
                            Circle()
                                .strokeBorder(
                                    myRing.allSeen
                                        ? AnyShapeStyle(IMColor.separator)
                                        : AnyShapeStyle(LinearGradient(
                                            colors: [IMColor.blue, Color(hex: "AF52DE")],
                                            startPoint: .topLeading, endPoint: .bottomTrailing)),
                                    lineWidth: myRing.allSeen ? 1.5 : 2.5)
                                .frame(width: 66, height: 66)
                            MediaImage(url: myRing.authorAvatarURL, cornerRadius: 27)
                                .frame(width: 54, height: 54)
                                .clipShape(Circle())
                        }
                    } else {
                        Circle()
                            .fill(IMColor.chrome)
                            .frame(width: 62, height: 62)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(IMColor.secondary))
                    }
                }
                .buttonStyle(.plain)

                if myRing != nil {
                    Button { compose() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(IMColor.blue))
                            .overlay(Circle().strokeBorder(IMColor.bg, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Your story")
                .font(.system(size: 12))
                .foregroundStyle(IMColor.secondary)
                .lineLimit(1)
        }
        .frame(width: 70)
    }

    private func compose() {
        app.worldComposerKind = "story"
        app.worldSheet = .composer
    }

    private func storyBubble(_ ring: WorldStoryRing) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .strokeBorder(
                        ring.allSeen
                            ? AnyShapeStyle(IMColor.separator)
                            : AnyShapeStyle(LinearGradient(
                                colors: [IMColor.blue, Color(hex: "AF52DE")],
                                startPoint: .topLeading, endPoint: .bottomTrailing)),
                        lineWidth: ring.allSeen ? 1.5 : 2.5)
                    .frame(width: 66, height: 66)
                MediaImage(url: ring.authorAvatarURL, cornerRadius: 27)
                    .frame(width: 54, height: 54)
                    .clipShape(Circle())
            }
            Text(app.worldAuthorName(ring))
                .font(.system(size: 12))
                .foregroundStyle(IMColor.label)
                .lineLimit(1)
        }
        .frame(width: 70)
    }

    private func sectionDivider(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(IMColor.secondary)
                .textCase(.uppercase)
            Rectangle()
                .fill(IMColor.separator.opacity(0.5))
                .frame(height: 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }
}

// MARK: - One post

struct WorldPostCard: View {
    @EnvironmentObject var app: AppState
    let post: WorldPost
    /// Set when the card itself sits in a horizontally swiping row. A second
    /// scroll view on the same axis would eat the swipe that pages the posts,
    /// so a multi-image post tiles rather than scrolls.
    var pagedHorizontally = false

    private var isMine: Bool { post.authorID == SocialStore.shared.myProfileId }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !post.text.isEmpty {
                Text(post.text)
                    .font(.system(size: 15))
                    .foregroundStyle(IMColor.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !post.imageURLs.isEmpty {
                media
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(IMColor.chrome.opacity(0.55)))
    }

    private var header: some View {
        HStack(spacing: 10) {
            MediaImage(url: post.authorAvatarURL, cornerRadius: 18)
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(app.worldAuthorName(post))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(IMColor.label)
                HStack(spacing: 5) {
                    WorldPostAge(date: post.createdAt)
                        .font(.system(size: 12))
                        .foregroundStyle(IMColor.secondary)
                    // Shown only on your own posts — a reader is never told
                    // which of the author's circles they landed in.
                    if let audience = post.audience {
                        Image(systemName: audience == .contacts ? "person.2.fill" : "circle.grid.2x2.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(IMColor.secondary)
                        Text(audience == .contacts ? "Contacts" : "Circles")
                            .font(.system(size: 12))
                            .foregroundStyle(IMColor.secondary)
                    }
                }
            }
            Spacer()
            if isMine {
                Menu {
                    Button("Delete post", role: .destructive) {
                        app.deleteWorldContent(post.id)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(IMColor.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    @ViewBuilder
    private var media: some View {
        if post.imageURLs.count == 1 {
            MediaImage(url: post.imageURLs[0], cornerRadius: 14)
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .clipped()
        } else if pagedHorizontally {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8),
                          GridItem(.flexible(), spacing: 8)],
                spacing: 8) {
                ForEach(post.imageURLs, id: \.self) { url in
                    MediaImage(url: url, cornerRadius: 14)
                        .frame(height: 116)
                        .clipped()
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(post.imageURLs, id: \.self) { url in
                        MediaImage(url: url, cornerRadius: 14)
                            .frame(width: 220, height: 240)
                            .clipped()
                    }
                }
            }
        }
    }
}

// MARK: - Post age

/// How long ago a post went up, counting up while it's on screen.
///
/// Seconds are only worth reading while a post is brand new. SwiftUI's
/// `.relative` style always spells out two units — "6 min, 8 secs" — so past a
/// minute the label drops to a single one, and the tick slows to match: a card
/// that reads "6 min" has nothing to say for another 60 seconds.
struct WorldPostAge: View {
    let date: Date

    var body: some View {
        let fresh = Date().timeIntervalSince(date) < 60
        // Anchored to the post rather than to now, so the label turns over on
        // the boundary itself instead of somewhere in the middle of the minute.
        TimelineView(.periodic(from: date, by: fresh ? 1 : 60)) { context in
            Text(Self.label(for: date, now: context.date))
        }
    }

    /// Abbreviated units past the first minute — "min", "hr" and "wk" read the
    /// same singular or plural, so only "sec" and "day" take an s.
    static func label(for date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60:
            let n = max(1, Int(seconds))
            return "\(n) sec\(n == 1 ? "" : "s")"
        case ..<3600:
            return "\(Int(seconds / 60)) min"
        case ..<86_400:
            return "\(Int(seconds / 3600)) hr"
        case ..<604_800:
            let n = Int(seconds / 86_400)
            return "\(n) day\(n == 1 ? "" : "s")"
        default:
            return "\(Int(seconds / 604_800)) wk"
        }
    }
}

// MARK: - Story viewer

/// Full-screen story playback. Deliberately minimal — the re-spec leaves the
/// chat detail screen alone and this is the only new full-screen surface.
struct WorldStoryViewer: View {
    @EnvironmentObject var app: AppState
    let ring: WorldStoryRing
    @State private var index = 0

    private var frame: WorldPost? {
        guard index >= 0, index < ring.frames.count else { return nil }
        return ring.frames[index]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let frame {
                VStack(spacing: 0) {
                    progressBars
                    header
                    Spacer(minLength: 0)
                    if let url = frame.imageURLs.first {
                        MediaImage(url: url, cornerRadius: 0, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                    }
                    if !frame.text.isEmpty {
                        Text(frame.text)
                            .font(.system(size: 17))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                            .padding(.top, 20)
                    }
                    Spacer(minLength: 0)
                }
            }
            // Tap right to advance, left to go back — the universal story gesture.
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture { step(-1) }
                Color.clear.contentShape(Rectangle()).onTapGesture { step(1) }
            }
        }
        .onAppear { markSeen() }
        .onChange(of: index) { _, _ in markSeen() }
    }

    private var progressBars: some View {
        HStack(spacing: 4) {
            ForEach(ring.frames.indices, id: \.self) { i in
                Capsule()
                    .fill(i <= index ? Color.white : Color.white.opacity(0.3))
                    .frame(height: 2.5)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private var header: some View {
        HStack(spacing: 10) {
            MediaImage(url: ring.authorAvatarURL, cornerRadius: 16)
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            Text(app.worldAuthorName(ring))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                app.openWorldStory = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private func step(_ delta: Int) {
        let next = index + delta
        if next < 0 { return }
        if next >= ring.frames.count {
            app.openWorldStory = nil
            return
        }
        index = next
    }

    private func markSeen() {
        if let frame { app.markWorldStorySeen(frame) }
    }
}
