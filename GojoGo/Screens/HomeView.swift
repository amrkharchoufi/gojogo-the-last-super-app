import SwiftUI
import PhotosUI
import UIKit

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var storyPicker: PhotosPickerItem?
    @State private var hideChrome = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    storyRail
                        .padding(.top, 4)
                        .padding(.bottom, 8)

                    ForEach(app.posts) { post in
                        InstagramPostCard(post: post)
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 0.5)
                    }

                    Color.clear.frame(height: tabBarInset)
                }
                .padding(.top, 52)
            }
            .trackScrollChrome(hidden: $hideChrome)

            // Top chrome — Instagram: wordmark left, actions right
            HStack(spacing: 16) {
                Wordmark(size: 22)
                Spacer()
                Button {
                    // Activity placeholder
                } label: {
                    Image(systemName: "heart")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { app.openOwnProfile() } label: {
                    UserAvatar(
                        size: 28,
                        gradient: app.user.avatarGradient,
                        letter: String(app.user.name.prefix(1)),
                        imageURL: app.user.avatarURL
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile")
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.92), Color.black.opacity(0.55), .clear],
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
                            Color.white.opacity(0.28),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                        .frame(width: 74, height: 74)
                    Text("+")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text("More")
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textSecondary)
                    .frame(width: 74)
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
                    size: 68,
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
                        .font(.system(size: 20))
                        .background(Circle().fill(.black).padding(2))
                        .offset(x: 2, y: 2)
                }
            }
            .frame(width: 74, height: 74)

            Text(story.isYou ? "Your story" : story.name)
                .font(.system(size: 11))
                .foregroundStyle(story.seen && !story.isYou ? GGColor.textTertiary : .white)
                .frame(width: 74)
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
    @State private var isMuted = true
    @State private var isHolding = false

    private var live: Post {
        app.posts.first(where: { $0.id == post.id }) ?? post
    }

    private var mediaHeight: CGFloat {
        // Instagram portrait feed (~4:5 — taller than square).
        let aspect = live.imageAspect > 0 ? live.imageAspect : 1.25
        let clamped = min(max(aspect, 1.15), 1.4)
        return UIScreen.main.bounds.width * clamped
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
        if live.isVideo {
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
                            .foregroundStyle(.white)
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
                            Capsule().fill(live.following ? Color.white.opacity(0.08) : Color.white.opacity(0.16))
                        )
                }
                .buttonStyle(.plain)
            }

            Menu {
                postContextMenu
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
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
        if live.imageURL != nil || live.imageData != nil || live.isVideo {
            ZStack {
                if let videoURL = live.videoURL, !videoURL.isEmpty {
                    MediaImage(url: live.imageURL, data: live.imageData, cornerRadius: 0)
                        .frame(maxWidth: .infinity)
                        .frame(height: mediaHeight)
                        .clipped()

                    ShortVideoPlayer(
                        urlString: videoURL,
                        isActive: !isHolding,
                        isMuted: isMuted
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: mediaHeight)
                    .clipped()
                } else {
                    MediaImage(url: live.imageURL, data: live.imageData, cornerRadius: 0)
                        .frame(maxWidth: .infinity)
                        .frame(height: mediaHeight)
                        .clipped()
                }

                HeartBurstOverlay(trigger: heartTrigger)

                if isHolding {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(16)
                        .background(Circle().fill(Color.black.opacity(0.4)))
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .allowsHitTesting(false)
                }

                if live.isVideo {
                    Button {
                        isMuted.toggle()
                    } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(10)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                _ = app.likePost(live.id)
                heartTrigger += 1
            }
            .onTapGesture {
                guard live.isVideo else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                app.openFeedVideoAsShort(postID: live.id)
            }
            .onLongPressGesture(
                minimumDuration: 0.2,
                maximumDistance: 12,
                pressing: { pressing in
                    guard live.isVideo else { return }
                    // Touch-down while scrolling must not vibrate — only clear pause on release.
                    if !pressing {
                        isHolding = false
                    }
                },
                perform: {
                    guard live.isVideo else { return }
                    isHolding = true
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            )
            .animation(.easeOut(duration: 0.12), value: isHolding)
        }
    }

    @ViewBuilder
    private var captionBlock: some View {
        if let text = live.text, !text.isEmpty {
            (Text(live.author).fontWeight(.semibold) + Text(" ") + Text(text))
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .lineSpacing(3)
                .lineLimit(3)
        } else if live.likeCount > 0 {
            Text("\(formatCount(live.likeCount)) likes")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
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

/// Kept as alias so older references keep compiling.
typealias FullPostCard = InstagramPostCard
