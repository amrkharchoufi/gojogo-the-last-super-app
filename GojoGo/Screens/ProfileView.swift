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

/// Profile content tabs. Each kind of thing this account publishes gets its own
/// tab and its own layout — a text note, a photo, a long-form video and a short
/// have nothing in common visually, and squeezing all four into one square grid
/// was flattening them into thumbnails that told you nothing.
/// Home (customizable canvas) is the landing tab; Saved is own-profile only.
private enum ProfileTab: Hashable {
    case home, posts, text, videos, shorts, saved

    /// Icons reuse the vocabulary the rest of the app already uses for each
    /// kind — `play.rectangle` is long-form in the composer and the dock,
    /// `rectangle.stack` is the Shorts pager's own empty-state glyph.
    var icon: String {
        switch self {
        case .home:   return "house"
        case .posts:  return "square.grid.3x3"
        case .text:   return "text.alignleft"
        case .videos: return "play.rectangle"
        case .shorts: return "rectangle.stack"
        case .saved:  return "bookmark"
        }
    }

    var emptyTitle: String {
        switch self {
        case .home:   return "Nothing here yet."
        case .posts:  return "No photos or videos yet."
        case .text:   return "No written posts yet."
        case .videos: return "No videos yet."
        case .shorts: return "No shorts yet."
        case .saved:  return "Nothing saved yet."
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject var app: AppState
    @State private var tab = 0
    /// Live offset while the back-swipe is in progress.
    @State private var backDrag: CGFloat = 0
    /// Measured width of the tab strip — decides whether the tabs spread to
    /// fill or start scrolling at their natural size.
    @State private var tabStripWidth: CGFloat = 0

    private var profile: ProfileUser {
        app.profileUser ?? .own(from: app.user, posts: app.myPosts.count)
    }

    private var isOwn: Bool { profile.isOwn }

    /// The id of the business being viewed, when it's one of yours.
    private var businessID: UUID? {
        guard profile.isBusinessOwner else { return nil }
        return app.ownedBusinesses.first { $0.handle.lowercased() == profile.handle.lowercased() }?.id
    }

    /// Tabs available for this profile. Everyone gets a customizable Home first.
    private var tabs: [ProfileTab] {
        isOwn
            ? [.home, .posts, .text, .videos, .shorts, .saved]
            : [.home, .posts, .text, .videos, .shorts]
    }

    private var selectedTab: ProfileTab {
        tabs.indices.contains(tab) ? tabs[tab] : .posts
    }

    /// Posts authored by the profile being viewed.
    private var profilePosts: [Post] {
        if isOwn { return app.myPosts }
        return app.posts.filter {
            $0.author == profile.handle || $0.author == "@\(profile.handle)"
        }
    }

    /// Written posts — text with nothing attached. These are the ones a square
    /// thumbnail served worst, so they get a readable list of their own.
    private var textPosts: [Post] {
        profilePosts.filter {
            $0.carouselSlides.isEmpty
                && !($0.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Posts that carry a photo, a carousel or a video — the grid's contents.
    private var mediaPosts: [Post] {
        profilePosts.filter { !$0.carouselSlides.isEmpty }
    }

    private var profileVideos: [VideoItem] {
        isOwn ? app.myVideos : app.videos.filter { matchesProfile($0.channel) }
    }

    private var profileShorts: [Short] {
        isOwn ? app.myShorts : app.shorts.filter { matchesProfile($0.channel) }
    }

    /// Home blocks for the profile: the live own layout, or the visited user's.
    private var homeBlocks: [ProfileHomeBlock] {
        isOwn ? app.profileHomeBlocks : app.otherProfileHome(profile.handle)
    }

    /// Cells for the tabs that render as a grid. Text and long-form have their
    /// own list layouts and never come through here.
    private var gridItems: [ProfileGridItem] {
        switch selectedTab {
        case .home, .text, .videos:
            return []
        case .posts:
            // Media only — a written post is not a blank tile here any more,
            // it lives in its own tab.
            return mediaPosts.map { post in
                ProfileGridItem(id: "post-\(post.id)",
                                kind: .image(url: post.imageURL, data: postThumbData(post)),
                                target: .post(post.id),
                                isCarousel: post.isCarousel,
                                isVideoPost: post.isVideo)
            }
        case .shorts:
            return profileShorts.map {
                ProfileGridItem(id: "short-\($0.id)",
                                kind: .video(url: $0.imageURL, data: $0.imageData, duration: nil),
                                target: .short($0.id),
                                views: $0.views)
            }
        case .saved:
            guard isOwn else { return [] }
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
    }

    /// Handle match for the profile being viewed, tolerant of a leading "@".
    private func matchesProfile(_ handle: String) -> Bool {
        handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
            == profile.handle.lowercased()
    }

    /// Best still to represent a post in a grid cell (poster, or first carousel slide).
    private func postThumbData(_ post: Post) -> Data? {
        post.imageData ?? post.mediaItems.first?.imageData
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

    /// Pull-to-refresh. Your own profile re-reads the feed it's built from and
    /// your follower/post counts; someone else's re-reads their public profile.
    /// Highlights are refetched either way — that's the part `.task` already
    /// owns, and the one most likely to have changed while the sheet was open.
    private func pullRefresh() async {
        let owner = isOwn ? nil : SocialStore.shared.profileId(forHandle: profile.handle)
        if isOwn {
            await app.refreshSocial()
            await app.refreshOwnCounts()
            app.profileUser = .own(from: app.user, posts: app.myPosts.count)
        } else {
            app.refreshRemoteProfile(handle: profile.handle)
        }
        guard isOwn || owner != nil else { return }
        await app.refreshHighlights(for: owner)
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

                    highlightsRow

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
            .refreshable { await pullRefresh() }
        }
        // Pushed page, so the system's own back-swipe isn't there — this
        // restores it. Confined to a narrow leading strip so it can never
        // fight the grid's vertical scroll or the highlights rail.
        .offset(x: backDrag)
        .overlay(alignment: .leading) {
            Color.clear
                .frame(width: 20)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            backDrag = max(0, value.translation.width)
                        }
                        .onEnded { value in
                            let far = value.translation.width > 90
                            let flick = value.predictedEndTranslation.width > 220
                            if far || flick {
                                app.closeProfile()
                            }
                            withAnimation(.ggSnappy) { backDrag = 0 }
                        }
                )
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
        .task(id: profile.handle) {
            // Someone else's highlights need their id; your own is the default.
            let owner = isOwn ? nil : SocialStore.shared.profileId(forHandle: profile.handle)
            guard isOwn || owner != nil else { return }
            await app.refreshHighlights(for: owner)
            // Their uploads populate the Videos and Shorts tabs — without this
            // those tabs would be empty for anyone you haven't watched.
            if let channel = owner ?? SocialStore.shared.myProfileId {
                await app.refreshChannelVideos(of: channel)
            }
        }
        .videoDeletionConfirmations()
        // These open from inside this sheet, so they must present from here.
        .sheet(isPresented: $app.showEditProfile) {
            EditProfileSheet().environmentObject(app)
        }
        // The identity switcher opens from this screen only — one owner per
        // AppState-driven sheet, or it silently refuses to present.
        .sheet(isPresented: $app.showBusinessProfiles) {
            BusinessProfilesView().environmentObject(app)
        }
        // Settings opens from this screen only — one owner per AppState-driven
        // sheet, or it silently refuses to present.
        .sheet(isPresented: $app.showSettings) {
            SettingsView().environmentObject(app)
        }
        // Both open from Settings, which opens from here — so they present from
        // here too. One owner per AppState-driven sheet, or it silently refuses.
        .sheet(isPresented: $app.showBlockedAccounts) {
            BlockedAccountsView().environmentObject(app)
        }
        .sheet(isPresented: $app.showDeleteAccount) {
            DeleteAccountView().environmentObject(app)
        }
        // Report and block open from this screen's menu, so they present from
        // here; the root's copy stands down while this page is up. A comments
        // thread opened *over* this profile owns them instead — it is a real
        // sheet, and this page cannot present over one.
        .safetyPresentations(active: app.commentingPostID == nil)
        // The wallet is presented by the root instead: delivery checkout opens
        // it too (a 402 offers a top-up), and the root is the one presenter
        // that is alive on every screen. It stands down while this profile
        // sheet is up — same gating shape as the story archive.
        .sheet(isPresented: Binding(
            get: { app.showWallet && app.showProfile },
            set: { app.showWallet = $0 }
        )) {
            WalletView().environmentObject(app)
        }
        .sheet(isPresented: Binding(
            get: { app.editingVideoID != nil },
            set: { if !$0 { app.closeVideoDetails() } }
        )) {
            if let id = app.editingVideoID {
                VideoDetailsSheet(target: .published(id)).environmentObject(app)
            }
        }
        // "New highlight" opens from this sheet, so it presents from here.
        .sheet(isPresented: $app.showStoryArchive) {
            StoryArchiveView().environmentObject(app)
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
            // A page needs a way back on *both* profiles — your own used to rely
            // on swiping the drawer down, which no longer exists. Composing
            // moved into the menu on the right rather than crowding this side.
            Button {
                app.closeProfile()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Text(profile.handle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                if isOwn {
                    // The chevron is the identity switcher now: you, or one of
                    // your business profiles (Phase 2e M1).
                    Button {
                        app.showBusinessProfiles = true
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(GGColor.ink(0.85))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else if profile.verified {
                    // Earned through a KYC'd partner approval — the only way
                    // this badge is ever granted.
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.ink(0.9))
                }
            }

            Spacer(minLength: 0)

            Menu {
                if isOwn {
                    Button {
                        app.closeProfile()
                        app.activeTab = .home
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            app.openComposer()
                        }
                    } label: {
                        Label("New post", systemImage: "plus.square")
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
                    Divider()
                    // Everything that is about the *account* rather than about
                    // this screen now lives one level down. This menu had been
                    // growing an entry per milestone — edit profile, business
                    // profiles, the wallet, the theme — which is how a menu
                    // becomes a drawer nobody can find anything in.
                    Button {
                        app.showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
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
                    // Both act on the account, and they are different things:
                    // reporting asks us to look, blocking is the person doing
                    // something about it themselves without waiting for us.
                    Button(role: .destructive) {
                        guard let id = SocialStore.shared.profileId(forHandle: profile.handle)
                        else { return }
                        app.openReport(.profile, id: id, label: "@\(profile.handle)")
                    } label: {
                        Label("Report account", systemImage: "flag")
                    }
                    if let id = SocialStore.shared.profileId(forHandle: profile.handle) {
                        if app.blockedAccounts.contains(where: { $0.id == id }) {
                            Button {
                                Task { await app.unblock(profileId: id) }
                            } label: {
                                Label("Unblock", systemImage: "hand.raised.slash")
                            }
                        } else {
                            Button(role: .destructive) {
                                app.confirmBlock(profileId: id, handle: profile.handle)
                            } label: {
                                Label("Block", systemImage: "hand.raised")
                            }
                        }
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

    // MARK: Story highlights

    /// Highlights sit between the bio and the content tabs, as on Instagram.
    /// Hidden entirely when there's nothing to show and it isn't your profile —
    /// an empty "New" bubble on someone else's page is noise.
    @ViewBuilder
    private var highlightsRow: some View {
        if !app.storyHighlights.isEmpty || isOwn {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    if isOwn {
                        Button { app.showStoryArchive = true } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .strokeBorder(GGColor.ink(0.25),
                                                      style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                        .frame(width: 62, height: 62)
                                    Image(systemName: "plus")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(GGColor.textSecondary)
                                }
                                Text("New")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(GGColor.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(app.storyHighlights) { highlight in
                        Button { app.openHighlight(highlight) } label: {
                            StoryHighlightBubble(highlight: highlight)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if isOwn {
                                Button(role: .destructive) {
                                    app.deleteHighlight(highlight.id)
                                } label: {
                                    Label("Delete highlight", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 16)
        }
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

            if profile.isBusiness, let business = profile.business, !business.isEmpty {
                businessBlock(business)
            }

            if isOwn, let acting = app.actingBusiness {
                Button {
                    app.showBusinessProfiles = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "briefcase.fill").font(.system(size: 11, weight: .semibold))
                        Text("Publishing as \(acting.name)")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(GGColor.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .glassCapsule()
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 6)
            }

            if !isOwn && !profile.isBusiness {
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

    /// Where a business is and how to reach it. Rendered from the profile view's
    /// business block — the app never stores a second copy of it.
    @ViewBuilder
    private func businessBlock(_ business: BusinessContact) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !business.addressSummary.isEmpty {
                businessLine("mappin.and.ellipse", business.addressSummary)
            }
            if !business.openingHours.isEmpty {
                businessLine("clock", business.openingHours)
            }
            if !business.phone.isEmpty {
                businessLine("phone", business.phone)
            }
            if !business.email.isEmpty {
                businessLine("envelope", business.email)
            }
            if !business.website.isEmpty {
                businessLine("link", business.website)
            }
        }
        .padding(.top, 6)
    }

    private func businessLine(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(GGColor.textSecondary)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            } else if profile.isBusinessOwner {
                // Your own business page: following yourself is meaningless, so
                // this is where you run it from.
                HStack(spacing: 8) {
                    profileButton(app.actingBusinessID == businessID ? "Publishing as this" : "Publish as this") {
                        if let businessID { app.actAsBusiness(businessID) }
                    }
                    profileButton("Manage") { app.showBusinessProfiles = true }
                    ShareLink(item: "https://gojogo.app/@\(profile.handle)") {
                        Text("Share")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(GGColor.ink(0.12)))
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

    /// Smallest a tab may ever get. Six tabs at this width overflow a phone, and
    /// that is the point: they keep their full tap target and the row scrolls
    /// instead of shrinking icons into an unreadable strip.
    private static let minTabWidth: CGFloat = 62

    /// One row that behaves two ways from a single layout, no branching: the
    /// strip is always horizontally scrollable, but its content is pinned to at
    /// least the container's width, so while the tabs fit they spread evenly
    /// edge to edge exactly as before — and only once they can't do they start
    /// scrolling at full size. The selected tab is always scrolled into view,
    /// and a fade on each edge shows there is more when there is.
    private var iconTabs: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(tabs.enumerated()), id: \.offset) { i, item in
                            tabButton(item, index: i)
                                .id(i)
                        }
                    }
                    .frame(minWidth: tabStripWidth, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .mask(tabEdgeFade)
                .onChange(of: tab) { _, newValue in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { tabStripWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, width in tabStripWidth = width }
                }
            }
            Rectangle().fill(GGColor.ink(0.12)).frame(height: 0.5)
        }
    }

    private func tabButton(_ item: ProfileTab, index: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeOut(duration: 0.2)) { tab = index }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(index == tab ? GGColor.textPrimary : GGColor.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                Rectangle()
                    .fill(index == tab ? GGColor.textPrimary : Color.clear)
                    .frame(height: 1.5)
            }
            .frame(minWidth: Self.minTabWidth, maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Only fades when the row actually overflows — a fade over tabs that fit
    /// would dim the first and last for no reason.
    private var tabEdgeFade: some View {
        let overflows = CGFloat(tabs.count) * Self.minTabWidth > tabStripWidth
        return LinearGradient(
            stops: overflows
                ? [.init(color: .clear, location: 0),
                   .init(color: .black, location: 0.045),
                   .init(color: .black, location: 0.955),
                   .init(color: .clear, location: 1)]
                : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
            startPoint: .leading, endPoint: .trailing
        )
    }

    // MARK: Grid

    @ViewBuilder
    private var contentGrid: some View {
        switch selectedTab {
        case .text:
            if textPosts.isEmpty { emptyTab } else { textList }
        case .videos:
            if profileVideos.isEmpty { emptyTab } else { videoList }
        case .shorts:
            if gridItems.isEmpty { emptyTab } else { reelsGrid }
        default:
            if gridItems.isEmpty { emptyTab } else { postsGrid }
        }
    }

    private var emptyTab: some View {
        Text(selectedTab.emptyTitle)
            .font(.system(size: 14))
            .foregroundStyle(GGColor.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 56)
    }

    // MARK: Written posts

    /// A readable feed of text-only posts. No repost control: this app has no
    /// reposting, and an icon for an action that doesn't exist is worse than
    /// no icon at all.
    private var textList: some View {
        LazyVStack(spacing: 0) {
            ForEach(textPosts) { post in
                textRow(post)
                Rectangle()
                    .fill(GGColor.ink(0.10))
                    .frame(height: 0.5)
                    .padding(.leading, 62)
            }
        }
    }

    private func textRow(_ post: Post) -> some View {
        HStack(alignment: .top, spacing: 12) {
            UserAvatar(size: 36,
                       gradient: profile.avatarGradient,
                       letter: String(profile.name.prefix(1)).uppercased(),
                       imageURL: profile.avatarURL)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(profile.handle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text(post.meta)
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textTertiary)
                    Spacer(minLength: 0)
                }

                MentionedText(text: post.text ?? "", mentions: post.mentions,
                              font: .system(size: 15),
                              color: GGColor.textPrimary) { handle, profileID in
                    app.openTaggedProfile(handle: handle, profileID: profileID)
                }
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 20) {
                    textAction(post.liked ? "heart.fill" : "heart",
                               tint: post.liked ? GGColor.red : GGColor.textSecondary,
                               count: post.likeCount) {
                        withAnimation(.easeOut(duration: 0.18)) { app.toggleLike(post.id) }
                    }
                    textAction("bubble.right", tint: GGColor.textSecondary,
                               count: app.commentsByPost[post.id]?.count ?? post.commentCount) {
                        app.openComments(for: post.id)
                    }
                    ShareLink(item: app.postShareURL(for: post.id)) {
                        Image(systemName: "paperplane")
                            .font(.system(size: 15))
                            .foregroundStyle(GGColor.textSecondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture { app.openPostViewer(post.id) }
        .contextMenu {
            Button { app.openPostViewer(post.id) } label: {
                Label("Open", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            ShareLink(item: app.postShareURL(for: post.id)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            if app.isMyPost(post.id) {
                Divider()
                Button(role: .destructive) {
                    app.requestDeletePost(post.id)
                } label: {
                    Label("Delete post", systemImage: "trash")
                }
            }
        }
    }

    private func textAction(_ icon: String, tint: Color, count: Int,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(tint)
                if count > 0 {
                    Text(formatCount(count))
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Long-form videos

    /// The Watch row, on the profile: a wide thumbnail with its duration, the
    /// title, and what it actually earned — views and age.
    private var videoList: some View {
        LazyVStack(spacing: 0) {
            ForEach(profileVideos) { video in
                videoRow(video)
            }
        }
    }

    private func videoRow(_ video: VideoItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                MediaImage(url: video.thumbURL, data: video.thumbData, cornerRadius: 10)
                    .frame(width: 150, height: 84)
                    .clipped()
                    .background(GGColor.ink(0.08))
                Text(video.duration)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.black.opacity(0.82)))
                    .padding(5)
            }
            .frame(width: 150, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(video.meta)
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)

            Menu {
                videoRowMenu(video)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(GGColor.textSecondary)
                    .frame(width: 28, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { open(.longForm(video.id)) }
        .contextMenu { videoRowMenu(video) }
    }

    @ViewBuilder
    private func videoRowMenu(_ video: VideoItem) -> some View {
        Button { open(.longForm(video.id)) } label: {
            Label("Play", systemImage: "play.fill")
        }
        ShareLink(item: app.videoShareURL(for: video.id), subject: Text(video.title)) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        if app.canDeleteVideo(video.id) {
            Divider()
            Button { app.editVideoDetails(video.id) } label: {
                Label("Edit details", systemImage: "pencil")
            }
            Button(role: .destructive) {
                app.requestDeleteVideo(video.id)
            } label: {
                Label("Delete video", systemImage: "trash")
            }
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 1.5), count: 3)
    }

    /// Square media grid. The corner badge is the only thing telling the three
    /// kinds apart at thumbnail size: stacked squares for a carousel, a play
    /// rectangle for a video — and deliberately nothing at all for a single
    /// photo, so the badge always means "there is more here than one image".
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
                            cornerBadge("play.rectangle.fill")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { open(item.target) }
                    .contextMenu { gridMenu(for: item) }
            }
        }
    }

    /// Portrait reels grid. The play count is what we actually counted, so a
    /// video nobody has opened shows nothing rather than an invented number.
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
                            if item.views > 0 {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(formatCount(item.views))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            if case .video(_, _, let duration) = item.kind, let duration {
                                Spacer(minLength: 4)
                                Text(duration)
                                    .font(.ggMono(11, .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(8)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { open(item.target) }
                    .contextMenu { gridMenu(for: item) }
            }
        }
    }

    /// Owner-only management on a grid cell. Deleting is the whole point here —
    /// there was no way to remove a short or a long-form video from anywhere.
    @ViewBuilder
    private func gridMenu(for item: ProfileGridItem) -> some View {
        if isOwn, let target = item.target {
            switch target {
            case .longForm(let id):
                Button { open(target) } label: { Label("Play", systemImage: "play.fill") }
                Button {
                    app.editVideoDetails(id)
                } label: {
                    Label("Edit details", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) {
                    app.requestDeleteVideo(id)
                } label: {
                    Label("Delete video", systemImage: "trash")
                }
            case .short(let id):
                Button { open(target) } label: { Label("Play", systemImage: "play.fill") }
                Divider()
                Button(role: .destructive) {
                    app.requestDeleteShort(id)
                } label: {
                    Label("Delete short", systemImage: "trash")
                }
            case .post(let id):
                Button { open(target) } label: {
                    Label("Open", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                if app.isMyPost(id) {
                    Divider()
                    Button(role: .destructive) {
                        app.requestDeletePost(id)
                    } label: {
                        Label("Delete post", systemImage: "trash")
                    }
                }
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
