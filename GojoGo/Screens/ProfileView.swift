import SwiftUI

private enum ProfileGridKind {
    case image(url: String?, data: Data?)
    case text(String)
    case video(url: String?, data: Data?, duration: String?)
}

private enum ProfileGridTarget {
    case post(UUID)
    case longForm(UUID)
    case short(UUID)
}

private struct ProfileGridItem: Identifiable {
    let id: String
    let kind: ProfileGridKind
    var target: ProfileGridTarget? = nil
    /// Posts-grid corner badge: multi-photo carousel.
    var isCarousel: Bool = false
    /// Posts-grid corner badge: video/reel.
    var isVideoPost: Bool = false
    /// Reels-grid overlay: play count.
    var views: Int = 0
}

/// Profile content tabs. Home (customizable canvas) is own-profile only.
private enum ProfileTab: Hashable {
    case home, grid, reels, saved

    var icon: String {
        switch self {
        case .home:  return "house"
        case .grid:  return "square.grid.3x3"
        case .reels: return "play.rectangle"
        case .saved: return "person.crop.square"
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0

    private var profile: ProfileUser {
        app.profileUser ?? .own(from: app.user, posts: app.myPosts.count)
    }

    private var isOwn: Bool { profile.isOwn }

    /// Tabs available for this profile. Everyone gets a customizable Home first.
    private var tabs: [ProfileTab] {
        isOwn ? [.home, .grid, .reels, .saved] : [.home, .grid, .reels]
    }

    private var selectedTab: ProfileTab {
        tabs.indices.contains(tab) ? tabs[tab] : .grid
    }

    /// Posts authored by the profile being viewed.
    private var profilePosts: [Post] {
        if isOwn { return app.myPosts }
        return app.posts.filter {
            $0.author == profile.handle || $0.author == "@\(profile.handle)"
        }
    }

    /// Home blocks for the profile: the live own layout, or the visited user's.
    private var homeBlocks: [ProfileHomeBlock] {
        isOwn ? app.profileHomeBlocks : app.otherProfileHome(profile.handle)
    }

    private var gridItems: [ProfileGridItem] {
        let posts: [Post] = {
            if isOwn { return app.myPosts }
            return app.posts.filter {
                $0.author == profile.handle || $0.author == "@\(profile.handle)"
            }
        }()

        switch selectedTab {
        case .home:
            return []
        case .grid:
            return posts.map { post in
                let hasImage = post.imageURL != nil || post.imageData != nil
                    || post.mediaItems.first?.imageData != nil
                let kind: ProfileGridKind = hasImage
                    ? .image(url: post.imageURL, data: postThumbData(post))
                    : .text(post.text ?? "Post")
                return ProfileGridItem(id: "post-\(post.id)",
                                       kind: kind,
                                       target: .post(post.id),
                                       isCarousel: post.isCarousel,
                                       isVideoPost: post.isVideo)
            }
        case .reels:
            if isOwn {
                // Every video the user posted, from any surface: Shorts, long-form
                // (Watch), and video feed posts — the last of which were missing.
                let shorts = app.myShorts.map {
                    ProfileGridItem(id: "short-\($0.id)",
                                    kind: .video(url: $0.imageURL, data: $0.imageData, duration: nil),
                                    target: .short($0.id),
                                    views: syntheticViews(likes: $0.likeCount, seed: $0.id.uuidString))
                }
                let videoPosts = app.myPosts.filter(\.isVideo).map {
                    ProfileGridItem(id: "reelpost-\($0.id)",
                                    kind: .video(url: $0.imageURL, data: postThumbData($0), duration: nil),
                                    target: .post($0.id),
                                    views: syntheticViews(likes: $0.likeCount, seed: $0.id.uuidString))
                }
                let longs = app.myVideos.map {
                    ProfileGridItem(id: "vid-\($0.id)",
                                    kind: .video(url: $0.thumbURL, data: $0.thumbData, duration: $0.duration),
                                    target: .longForm($0.id),
                                    views: syntheticViews(likes: $0.likes, seed: $0.id.uuidString))
                }
                return shorts + videoPosts + longs
            }
            return posts.filter(\.isVideo).map {
                ProfileGridItem(id: "reel-\($0.id)",
                                kind: .video(url: $0.imageURL, data: postThumbData($0), duration: nil),
                                target: .post($0.id),
                                views: syntheticViews(likes: $0.likeCount, seed: $0.id.uuidString))
            }
        case .saved:
            if isOwn {
                return app.savedPosts.prefix(12).map { post in
                    if post.imageURL != nil || post.imageData != nil {
                        return ProfileGridItem(id: "saved-\(post.id)",
                                               kind: .image(url: post.imageURL, data: post.imageData),
                                               target: .post(post.id))
                    }
                    return ProfileGridItem(id: "saved-\(post.id)",
                                           kind: .text(post.text ?? "Saved"),
                                           target: .post(post.id))
                }
            }
            return []
        }
    }

    /// Best still to represent a post in a grid cell (poster, or first carousel slide).
    private func postThumbData(_ post: Post) -> Data? {
        post.imageData ?? post.mediaItems.first?.imageData
    }

    /// Stable, realistic-looking play count for demo media (no real analytics yet).
    private func syntheticViews(likes: Int, seed: String) -> Int {
        var h = 5381
        for b in seed.utf8 { h = ((h &* 33) &+ Int(b)) & 0x7fffffff }
        return likes > 0 ? likes * 12 + (h % 4000) : (h % 60000) + 300
    }

    private func open(_ target: ProfileGridTarget?) {
        guard let target else { return }
        switch target {
        case .post(let id):
            app.openPostViewer(id)
        case .longForm(let id):
            // Video player presents from the main view — leave the profile sheet first.
            app.closeProfile()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                app.playVideo(id)
            }
        case .short(let id):
            app.closeProfile()
            app.focusedShortID = id
            withAnimation(.easeOut(duration: 0.25)) {
                app.activeTab = .watch
                app.watchSubFeed = .shorts
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    headerRow
                    profileHeader
                    bioBlock
                    actionsRow
                        .padding(.horizontal, 14)
                        .padding(.top, 12)

                    Section {
                        if selectedTab == .home {
                            ProfileHomeTab(isOwn: isOwn, blocks: homeBlocks)
                        } else {
                            contentGrid
                        }
                    } header: {
                        iconTabs
                            .padding(.top, 14)
                            .background(GGColor.bg)
                    }
                }
                .padding(.bottom, 28)
            }
            .background(GGColor.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            if app.profileUser == nil {
                app.profileUser = .own(from: app.user, posts: app.myPosts.count)
            }
            app.user.postCount = app.myPosts.count
            if !isOwn {
                app.ensureOtherProfileHome(handle: profile.handle, posts: profilePosts)
            }
        }
        // These open from inside this sheet, so they must present from here.
        .sheet(isPresented: $app.showEditProfile) {
            EditProfileSheet().environmentObject(app)
        }
        .sheet(isPresented: Binding(
            get: { app.dmPeer != nil },
            set: { if !$0 { app.closeDirectMessage() } }
        )) {
            DirectMessageView()
                .environmentObject(app)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: Binding(
            get: { app.viewingPostID != nil },
            set: { if !$0 { app.closePostViewer() } }
        )) {
            PostViewerSheet().environmentObject(app)
        }
        .sheet(isPresented: $app.showHomeBlockPicker) {
            ProfileHomeBlockPicker()
                .environmentObject(app)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(GGColor.sheetBG)
        }
        .sheet(isPresented: Binding(
            get: { app.editingHomeBlockID != nil },
            set: { if !$0 { app.editingHomeBlockID = nil } }
        )) {
            if let block = app.editingHomeBlock {
                ProfileHomeBlockEditor(block: block)
                    .environmentObject(app)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(GGColor.sheetBG)
            }
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
                        .foregroundStyle(GGColor.textPrimary)
                        .frame(width: 36, height: 36)
                }
            } else {
                Button {
                    app.closeProfile()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .frame(width: 36, height: 36)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Text(profile.handle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                if isOwn {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(GGColor.ink(0.85))
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.ink(0.9))
                }
            }

            Spacer(minLength: 0)

            Menu {
                if isOwn {
                    Button {
                        app.showEditProfile = true
                    } label: {
                        Label("Edit profile", systemImage: "pencil")
                    }
                    Button {
                        if let i = tabs.firstIndex(of: .saved) {
                            withAnimation(.easeOut(duration: 0.2)) { tab = i }
                        }
                    } label: {
                        Label("Saved", systemImage: "bookmark")
                    }
                    ShareLink(item: URL(string: "https://gojogo.app/@\(profile.handle)")!) {
                        Label("Share profile", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        app.toggleTheme()
                    } label: {
                        Label(app.appTheme == .dark ? "Light mode" : "Dark mode",
                              systemImage: app.appTheme == .dark ? "sun.max" : "moon")
                    }
                    Divider()
                    Button(role: .destructive) {
                        app.signOut()
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    ShareLink(item: URL(string: "https://gojogo.app/@\(profile.handle)")!) {
                        Label("Share profile", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = "https://gojogo.app/@\(profile.handle)"
                    } label: {
                        Label("Copy link", systemImage: "link")
                    }
                    Divider()
                    Button(role: .destructive) {
                        app.closeProfile()
                        dismiss()
                    } label: {
                        Label("Report", systemImage: "flag")
                    }
                }
            } label: {
                Image(systemName: isOwn ? "line.3.horizontal" : "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
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
                .foregroundStyle(GGColor.textPrimary)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Bio

    private var bioBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profile.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
            Text(profile.category)
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textSecondary)
            Text(profile.bio)
                .font(.system(size: 14))
                .foregroundStyle(GGColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !isOwn {
                HStack(spacing: 6) {
                    Circle().fill(GGColor.ink(0.35)).frame(width: 18, height: 18)
                    (Text("Followed by ")
                     + Text("friends on gojogo").fontWeight(.semibold))
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.ink(0.9))
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
                    profileButton("Edit profile") { app.showEditProfile = true }
                    ShareLink(item: "https://gojogo.app/@\(profile.handle)") {
                        Text("Share profile")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(GGColor.ink(0.12)))
                    }
                    profileButton("Activity") {
                        app.closeProfile()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            app.openActivity()
                        }
                    }
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
                            .foregroundStyle(profile.following ? GGColor.textPrimary : GGColor.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(profile.following ? GGColor.ink(0.14) : GGColor.white)
                            )
                    }
                    .buttonStyle(PressableStyle())

                    profileButton("Message") {
                        app.openDirectMessage(
                            handle: profile.handle,
                            name: profile.name,
                            avatarURL: profile.avatarURL,
                            avatarGradient: profile.avatarGradient
                        )
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeOut(duration: 0.2)) {
                            app.toggleNotify(handle: profile.handle)
                        }
                    } label: {
                        Image(systemName: app.notifyHandles.contains(profile.handle.lowercased())
                              ? "bell.fill" : "bell")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                            .frame(width: 40, height: 34)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(app.notifyHandles.contains(profile.handle.lowercased())
                                      ? GGColor.ink(0.24) : GGColor.ink(0.12)))
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
                .foregroundStyle(GGColor.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(GGColor.ink(0.12)))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Tabs

    private var iconTabs: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { i, item in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeOut(duration: 0.2)) { tab = i }
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: item.icon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(i == tab ? GGColor.textPrimary : GGColor.textTertiary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                            Rectangle()
                                .fill(i == tab ? GGColor.textPrimary : Color.clear)
                                .frame(height: 1.5)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Rectangle().fill(GGColor.ink(0.12)).frame(height: 0.5)
        }
    }

    // MARK: Grid

    private var contentGrid: some View {
        Group {
            if gridItems.isEmpty {
                Text("No posts yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(GGColor.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 56)
            } else if selectedTab == .reels {
                reelsGrid
            } else {
                postsGrid
            }
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 1.5), count: 3)
    }

    /// Square photo grid with carousel / video corner badges.
    private var postsGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 1.5) {
            ForEach(gridItems) { item in
                thumbBase(item)
                    .aspectRatio(1, contentMode: .fit)
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        if item.isCarousel {
                            cornerBadge("square.on.square.fill")
                        } else if item.isVideoPost {
                            cornerBadge("play.fill")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { open(item.target) }
            }
        }
    }

    /// Portrait reels grid with a play-count overlay.
    private var reelsGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 1.5) {
            ForEach(gridItems) { item in
                thumbBase(item)
                    .aspectRatio(3.0 / 5.0, contentMode: .fit)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .black.opacity(0.5)],
                                       startPoint: .center, endPoint: .bottom)
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(formatCount(item.views))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(8)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { open(item.target) }
            }
        }
    }

    private func cornerBadge(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .padding(7)
    }

    @ViewBuilder
    private func thumbBase(_ item: ProfileGridItem) -> some View {
        switch item.kind {
        case .image(let url, let data):
            MediaImage(url: url, data: data, cornerRadius: 0)
        case .video(let url, let data, _):
            MediaImage(url: url, data: data, cornerRadius: 0)
        case .text(let text):
            ZStack(alignment: .topLeading) {
                GGColor.ink(0.08)
                Text(text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GGColor.textPrimary)
                    .lineLimit(5)
                    .padding(8)
            }
        }
    }
}
