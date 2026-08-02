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

    var body: some View {
        VStack(spacing: 0) {
            if !app.worldStories.isEmpty || app.worldSetupComplete {
                storiesRow
            }
            if !app.worldFeedPosts.isEmpty {
                ForEach(app.worldFeedPosts) { post in
                    WorldPostCard(post: post)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                }
                sectionDivider("Messages")
            }
        }
    }

    // MARK: Stories

    private var storiesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                addStoryBubble
                ForEach(app.worldStories) { ring in
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

    private var addStoryBubble: some View {
        Button {
            app.worldSheet = .composer
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(IMColor.chrome)
                        .frame(width: 62, height: 62)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(IMColor.secondary))
                }
                Text("Your story")
                    .font(.system(size: 12))
                    .foregroundStyle(IMColor.secondary)
                    .lineLimit(1)
            }
            .frame(width: 70)
        }
        .buttonStyle(.plain)
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
                    Text(post.createdAt, style: .relative)
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
