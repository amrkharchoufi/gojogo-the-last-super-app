import SwiftUI

private enum ProfileGridKind {
    case image(url: String?, data: Data?)
    case text(String)
    case video(url: String?, data: Data?, duration: String?)
}

private struct ProfileGridItem: Identifiable {
    let id: String
    let kind: ProfileGridKind
}

struct ProfileView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0

    private var profile: ProfileUser {
        app.profileUser ?? .own(from: app.user, posts: app.myPosts.count)
    }

    private var isOwn: Bool { profile.isOwn }

    private var gridItems: [ProfileGridItem] {
        let posts: [Post] = {
            if isOwn { return app.myPosts }
            return app.posts.filter {
                $0.author == profile.handle || $0.author == "@\(profile.handle)"
            }
        }()

        switch tab {
        case 0:
            return posts.map { post in
                if post.imageURL != nil || post.imageData != nil {
                    return ProfileGridItem(id: "post-\(post.id)",
                                           kind: .image(url: post.imageURL, data: post.imageData))
                }
                return ProfileGridItem(id: "post-\(post.id)",
                                       kind: .text(post.text ?? "Post"))
            }
        case 1:
            if isOwn {
                let longs = app.myVideos.map {
                    ProfileGridItem(id: "vid-\($0.id)",
                                    kind: .video(url: $0.thumbURL, data: $0.thumbData, duration: $0.duration))
                }
                let shorts = app.myShorts.map {
                    ProfileGridItem(id: "short-\($0.id)",
                                    kind: .video(url: $0.imageURL, data: $0.imageData, duration: nil))
                }
                return longs + shorts
            }
            return posts.filter { $0.imageURL != nil || $0.imageData != nil }.map {
                ProfileGridItem(id: "reel-\($0.id)",
                                kind: .video(url: $0.imageURL, data: $0.imageData, duration: nil))
            }
        case 2:
            if isOwn {
                return app.savedPosts.prefix(12).map { post in
                    if post.imageURL != nil || post.imageData != nil {
                        return ProfileGridItem(id: "saved-\(post.id)",
                                               kind: .image(url: post.imageURL, data: post.imageData))
                    }
                    return ProfileGridItem(id: "saved-\(post.id)",
                                           kind: .text(post.text ?? "Saved"))
                }
            }
            return []
        default:
            return []
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerRow
                    profileHeader
                    bioBlock
                    actionsRow
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                    iconTabs
                        .padding(.top, 14)
                    contentGrid
                }
                .padding(.bottom, 28)
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if app.profileUser == nil {
                app.profileUser = .own(from: app.user, posts: app.myPosts.count)
            }
            app.user.postCount = app.myPosts.count
        }
    }

    // MARK: Top bar

    private var headerRow: some View {
        HStack(spacing: 14) {
            if isOwn {
                Button {
                    app.closeProfile()
                    app.activeTab = .home
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        app.openComposer()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
            } else {
                Button {
                    app.closeProfile()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Text(profile.handle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                if isOwn {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            Spacer(minLength: 0)

            Button {} label: {
                Image(systemName: isOwn ? "line.3.horizontal" : "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: Avatar + stats

    private var profileHeader: some View {
        HStack(alignment: .center, spacing: 24) {
            ZStack(alignment: .bottomTrailing) {
                UserAvatar(
                    size: 86,
                    gradient: profile.avatarGradient,
                    letter: String(profile.name.prefix(1)),
                    imageURL: profile.avatarURL
                )
                if isOwn {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.black, .white)
                        .font(.system(size: 22))
                        .background(Circle().fill(.black).padding(2))
                        .offset(x: 2, y: 2)
                }
            }

            HStack(spacing: 0) {
                stat(formatCount(profile.postCount), "posts")
                stat(formatCount(profile.followerCount), "followers")
                stat(formatCount(profile.followingCount), "following")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Bio

    private var bioBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profile.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text(profile.category)
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textSecondary)
            Text(profile.bio)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if !isOwn {
                HStack(spacing: 6) {
                    Circle().fill(Color.white.opacity(0.35)).frame(width: 18, height: 18)
                    (Text("Followed by ")
                     + Text("friends on gojogo").fontWeight(.semibold))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: Actions

    private var actionsRow: some View {
        Group {
            if isOwn {
                HStack(spacing: 8) {
                    profileButton("Edit profile") {}
                    ShareLink(item: "https://gojogo.app/@\(profile.handle)") {
                        Text("Share profile")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.12)))
                    }
                    profileButton("Email") {}
                }
            } else {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            app.toggleProfileFollow()
                        }
                    } label: {
                        Text(profile.following ? "Following" : "Follow")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(profile.following ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(profile.following ? Color.white.opacity(0.14) : Color.white)
                            )
                    }
                    .buttonStyle(PressableStyle())

                    profileButton("Message") {}

                    Button {} label: {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 34)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private func profileButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Tabs

    private var iconTabs: some View {
        let icons = isOwn
            ? ["square.grid.3x3", "play.rectangle", "person.crop.square"]
            : ["square.grid.3x3", "play.rectangle", "person.crop.square"]
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(icons.enumerated()), id: \.offset) { i, icon in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { tab = i }
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: icon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(i == tab ? .white : .white.opacity(0.35))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                            Rectangle()
                                .fill(i == tab ? Color.white : Color.clear)
                                .frame(height: 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5)
        }
    }

    // MARK: Grid

    private var contentGrid: some View {
        Group {
            if gridItems.isEmpty {
                Text(isOwn ? "No posts yet." : "No posts yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(GGColor.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 56)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 1.5), count: 3),
                    spacing: 1.5
                ) {
                    ForEach(gridItems) { item in
                        gridCell(item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func gridCell(_ item: ProfileGridItem) -> some View {
        switch item.kind {
        case .image(let url, let data):
            MediaImage(url: url, data: data, cornerRadius: 0)
                .aspectRatio(1, contentMode: .fit)
        case .text(let text):
            ZStack(alignment: .topLeading) {
                Color.white.opacity(0.08)
                Text(text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(5)
                    .padding(8)
            }
            .aspectRatio(1, contentMode: .fit)
        case .video(let url, let data, let duration):
            ZStack(alignment: .bottomLeading) {
                MediaImage(url: url, data: data, cornerRadius: 0)
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .padding(8)
                if let duration {
                    Text(duration)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()
        }
    }
}
