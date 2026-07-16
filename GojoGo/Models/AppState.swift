import SwiftUI

@MainActor
final class AppState: ObservableObject {
    // Auth / onboarding
    @Published var phase: AuthPhase = .welcome
    @Published var onboardingStep: Int = 1
    @Published var email: String = ""

    // Main navigation
    @Published var activeTab: AppTab = .home
    @Published var watchSubFeed: WatchSubFeed = .feed
    @Published var showProfile: Bool = false
    @Published var profileUser: ProfileUser? = nil
    @Published var showStoriesBrowser: Bool = false
    @Published var showWatching: Bool = false
    @Published var watchingWithMadeleine: Bool = false
    @Published var showCompose: Bool = false   // legacy sheet flag — prefer isComposing
    @Published var isComposing: Bool = false
    @Published var showAttachMenu: Bool = false
    @Published var composeText: String = ""
    @Published var composeAttachments: [ComposeAttachment] = []
    @Published var editingAttachmentID: UUID? = nil
    @Published var viewingStory: Story? = nil
    @Published var viewingFrameIndex: Int = 0
    /// When true, story is shown as an in-app overlay (not a system cover).
    @Published var storyOverlayActive: Bool = false
    /// Frozen author order for the current viewer session (Instagram-style).
    private var storyViewerRail: [UUID] = []
    @Published var messagingProduct: Product? = nil
    @Published var browsingProduct: Product? = nil
    @Published var sellerChat: [ChatMessage] = []
    @Published var sellerDraft: String = ""
    @Published var showSellSheet: Bool = false
    @Published var selectedTVShow: TVShow? = nil
    @Published var tvShows: [TVShow] = SampleData.tvShows
    @Published var tvHero: TVShow = SampleData.tvHero
    @Published var commentingPostID: UUID? = nil
    @Published var watchingVideoID: UUID? = nil
    @Published var watchingChat: [ChatMessage] = SampleData.watchingChat
    @Published var watchingDraft: String = ""
    /// When set, ShortsView jumps to this short (e.g. opened from a feed video).
    @Published var focusedShortID: UUID? = nil
    @Published var commentsByPost: [UUID: [Comment]] = [:]
    @Published var draftComment: String = ""

    // User + content (live, mutable)
    @Published var user = GGUser()
    @Published var interests: [Interest] = SampleData.interests
    @Published var stories: [Story] = SampleData.stories
    @Published var posts: [Post] = SampleData.posts
    @Published var videos: [VideoItem] = SampleData.videos
    @Published var shorts: [Short] = SampleData.shorts
    @Published var products: [Product] = SampleData.products
    @Published var featuredProduct: Product = SampleData.featuredProduct
    @Published var people: [PersonSuggestion] = SampleData.people
    @Published var profilePhotos: [String] = SampleData.profileGridURLs
    @Published var savedPostIDs: Set<UUID> = []
    @Published var chatMessages: [ChatMessage] = []

    // GojoTravel
    @Published var travelPhase: TravelPhase = .home
    @Published var travelPickup: TravelPlace = SampleData.travelDefaultCenter
    @Published var travelDropoff: TravelPlace? = nil
    @Published var travelQuery: String = ""
    @Published var travelRideOptions: [RideOption] = []
    @Published var selectedRide: RideOption? = nil
    @Published var travelDriver: TravelDriver? = nil
    @Published var travelRating: Int = 0
    @Published var travelRecent: [TravelPlace] = SampleData.travelRecentPlaces
    private var travelMatchTask: Task<Void, Never>?

    private var persistTask: Task<Void, Never>?

    var selectedInterestCount: Int { interests.filter(\.selected).count }

    /// Stories tray order: You → unwatched → watched (like Instagram).
    var storyTray: [Story] {
        let you = stories.filter(\.isYou)
        let others = stories.filter { !$0.isYou }
        let fresh = others.filter { $0.hasMedia && !$0.seen }
        let done = others.filter { $0.hasMedia && $0.seen }
        let empty = others.filter { !$0.hasMedia }
        return you + fresh + done + empty
    }

    var halfPosts: [Post] { posts.filter(\.isHalfWidth) }
    var fullPosts: [Post] { posts.filter { !$0.isHalfWidth } }
    var myPosts: [Post] {
        posts.filter { $0.author == user.handle || $0.author == "@\(user.handle)" }
    }
    var savedPosts: [Post] { posts.filter { savedPostIDs.contains($0.id) || $0.bookmarked } }
    var myVideos: [VideoItem] { videos.filter { $0.channel == user.handle } }
    var myShorts: [Short] { shorts.filter { $0.channel == user.handle } }
    var savedVideos: [VideoItem] { videos.filter(\.saved) }
    var savedShorts: [Short] { shorts.filter(\.bookmarked) }

    init() {
        if let cached = SessionStore.load() {
            applyCachedSession(cached)
            return
        }
        bootstrapFreshSession()
    }

    private func bootstrapFreshSession() {
        commentsByPost = SampleData.seedComments(for: posts)
        for i in posts.indices {
            posts[i].commentCount = commentsByPost[posts[i].id]?.count ?? 0
        }
        // Seed the profile with real own posts for the current handle
        let own = SampleData.ownSeedPosts(
            handle: user.handle,
            name: user.name,
            avatarURL: user.avatarURL,
            avatarGradient: user.avatarGradient)
        posts.insert(contentsOf: own, at: 0)
        user.postCount = myPosts.count

        // Seed one saved item so Saved isn't empty out of the box
        if let i = posts.firstIndex(where: { $0.author == "marta.st" }) {
            posts[i].bookmarked = true
            savedPostIDs.insert(posts[i].id)
        }
        if let i = videos.firstIndex(where: { $0.channel == "kal.eb" }) {
            videos[i].saved = true
        }
    }

    private func applyCachedSession(_ cached: CachedSession) {
        email = cached.email
        user = cached.user.asDomain()
        interests = cached.interests.map { $0.asDomain() }
        stories = cached.stories.map { $0.asDomain() }
        posts = cached.posts.map {
            var p = $0.asDomain()
            p.videoURL = VideoLibrary.normalizeStored(p.videoURL)
            return p
        }
        videos = cached.videos.map {
            var v = $0.asDomain()
            v.videoURL = VideoLibrary.normalizeStored(v.videoURL)
            return v
        }
        shorts = cached.shorts.map {
            var s = $0.asDomain()
            s.videoURL = VideoLibrary.normalizeStored(s.videoURL)
            return s
        }
        products = cached.products.map { $0.asDomain() }
        featuredProduct = cached.featuredProduct.asDomain()
        people = cached.people.map { $0.asDomain() }
        profilePhotos = cached.profilePhotos
        savedPostIDs = Set(cached.savedPostIDs)
        commentsByPost = Dictionary(uniqueKeysWithValues:
            cached.comments.map { ($0.postID, $0.comments.map { $0.asDomain() }) })
        chatMessages = cached.chatMessages.map { $0.asDomain() }
        activeTab = {
            switch cached.activeTabRaw {
            case "watch": return .watch
            case "madeleine": return .madeleine
            case "travel": return .travel
            case "economy": return .economy
            case "search": return .search
            default: return .home
            }
        }()
        watchSubFeed = WatchSubFeed(rawValue: cached.watchSubFeedRaw) ?? .feed
        phase = .app
        onboardingStep = 3
        // Rewrite durable relative video refs after migration.
        schedulePersist()
    }

    /// Writes the current connected session to disk.
    func persistSession() {
        guard phase == .app else { return }
        SessionStore.save(CachedSession(snapshotting: self))
    }

    /// Debounced save after mutations while connected.
    func schedulePersist() {
        guard phase == .app else { return }
        persistTask?.cancel()
        persistTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            persistSession()
        }
    }

    var commentingPost: Post? {
        guard let id = commentingPostID else { return nil }
        return posts.first(where: { $0.id == id })
    }

    var watchingVideo: VideoItem? {
        guard let id = watchingVideoID else { return nil }
        return videos.first(where: { $0.id == id })
    }

    // MARK: Onboarding

    func toggleInterest(_ id: UUID) {
        guard let i = interests.firstIndex(where: { $0.id == id }) else { return }
        interests[i].selected.toggle()
    }

    func finishOnboarding() {
        user.interests = interests.filter(\.selected).map(\.title)
        remapOwnContentToCurrentHandle()
        user.postCount = myPosts.count
        withAnimation(.easeInOut(duration: 0.5)) { phase = .app }
        persistSession()
    }

    private func remapOwnContentToCurrentHandle() {
        let seedTexts: Set<String> = [
            "First frames on gojogo — more coming.",
            "Studio light tests. Saving the ones that stay.",
            "Building in public. Notes later.",
        ]
        for i in posts.indices {
            guard let text = posts[i].text, seedTexts.contains(text) else { continue }
            let old = posts[i]
            posts[i] = Post(
                id: old.id,
                author: user.handle,
                meta: old.meta,
                avatarGradient: user.avatarGradient,
                avatarURL: user.avatarURL,
                imageURL: old.imageURL,
                imageData: old.imageData,
                videoURL: old.videoURL,
                imageAspect: old.imageAspect,
                text: old.text,
                bookmarked: old.bookmarked,
                likeCount: old.likeCount,
                commentCount: old.commentCount
            )
        }
    }

    func advanceOnboarding() {
        if onboardingStep < 3 {
            withAnimation(.easeInOut(duration: 0.35)) { onboardingStep += 1 }
        } else {
            finishOnboarding()
        }
    }

    // MARK: Posts

    func toggleLike(_ id: UUID) {
        guard let i = posts.firstIndex(where: { $0.id == id }) else { return }
        posts[i].liked.toggle()
        posts[i].likeCount += posts[i].liked ? 1 : -1
        schedulePersist()
    }

    /// Like only (Instagram double-tap) — no-ops if already liked. Returns whether newly liked.
    @discardableResult
    func likePost(_ id: UUID) -> Bool {
        guard let i = posts.firstIndex(where: { $0.id == id }) else { return false }
        guard !posts[i].liked else { return false }
        posts[i].liked = true
        posts[i].likeCount += 1
        schedulePersist()
        return true
    }

    func toggleBookmark(_ id: UUID) {
        guard let i = posts.firstIndex(where: { $0.id == id }) else { return }
        posts[i].bookmarked.toggle()
        if posts[i].bookmarked { savedPostIDs.insert(id) }
        else { savedPostIDs.remove(id) }
        schedulePersist()
    }

    func toggleFollow(postID: UUID) {
        guard let i = posts.firstIndex(where: { $0.id == postID }) else { return }
        posts[i].following.toggle()
        user.followingCount += posts[i].following ? 1 : -1
        schedulePersist()
    }

    func hidePost(_ id: UUID) {
        posts.removeAll { $0.id == id }
        savedPostIDs.remove(id)
        schedulePersist()
    }

    func postShareURL(for id: UUID) -> URL {
        URL(string: "https://gojogo.app/p/\(id.uuidString.lowercased())")!
    }

    func openComments(for postID: UUID) {
        commentingPostID = postID
        draftComment = ""
        if commentsByPost[postID] == nil {
            commentsByPost[postID] = SampleData.defaultComments
        }
    }

    func closeComments() {
        commentingPostID = nil
        draftComment = ""
    }

    func addComment() {
        guard let id = commentingPostID else { return }
        let text = draftComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let comment = Comment(author: user.handle, text: text,
                              avatarURL: user.avatarURL, timeAgo: "now")
        var list = commentsByPost[id] ?? []
        list.insert(comment, at: 0)
        commentsByPost[id] = list
        if let i = posts.firstIndex(where: { $0.id == id }) {
            posts[i].commentCount = list.count
        }
        draftComment = ""
        schedulePersist()
    }

    func toggleCommentLike(postID: UUID, commentID: UUID) {
        guard var list = commentsByPost[postID],
              let i = list.firstIndex(where: { $0.id == commentID }) else { return }
        list[i].liked.toggle()
        list[i].likeCount += list[i].liked ? 1 : -1
        commentsByPost[postID] = list
        schedulePersist()
    }

    func playVideo(_ id: UUID) {
        watchingVideoID = id
        watchingWithMadeleine = false
        watchingDraft = ""
        watchingChat = SampleData.watchingChat
        showWatching = true
    }

    /// Opens a feed video post in Shorts (creates a short entry if needed).
    func openFeedVideoAsShort(postID: UUID) {
        guard let post = posts.first(where: { $0.id == postID }),
              let url = post.videoURL, !url.isEmpty else { return }

        if let existing = shorts.first(where: { $0.videoURL == url }) {
            focusedShortID = existing.id
        } else {
            let short = Short(
                channel: post.author,
                subscribers: "from feed · just now",
                caption: post.text ?? post.author,
                gradient: post.avatarGradient,
                imageURL: post.imageURL,
                imageData: post.imageData,
                videoURL: url,
                likeCount: post.likeCount
            )
            shorts.insert(short, at: 0)
            focusedShortID = short.id
            schedulePersist()
        }

        withAnimation(.easeOut(duration: 0.25)) {
            activeTab = .watch
            watchSubFeed = .shorts
        }
    }

    func closeWatching() {
        LongFormOrientation.lock(.portrait)
        showWatching = false
        watchingVideoID = nil
        watchingWithMadeleine = false
        watchingDraft = ""
    }

    func openMadeleineWhileWatching() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            watchingWithMadeleine = true
        }
    }

    func sendWatchingChat() {
        let text = watchingDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        watchingChat.append(ChatMessage(text: text, fromUser: true))
        watchingDraft = ""
        let lower = text.lowercased()
        let reply: String
        if lower.contains("summar") || lower.contains("paper") {
            reply = "Here’s the gist: three papers cited — the 2024 toolformer study carries most of the argument. Want the PDF?"
        } else if lower.contains("who") || lower.contains("channel") {
            reply = "You’re watching \(watchingVideo?.channel ?? "this channel"). I can pull their other videos if you want."
        } else {
            reply = "Noted while we watch. Ask me to summarize, find sources, or queue related videos."
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            self?.watchingChat.append(ChatMessage(text: reply, fromUser: false))
            if lower.contains("summar") || lower.contains("paper") {
                self?.watchingChat.append(ChatMessage(
                    text: "", fromUser: false,
                    fileChip: FileChip(name: "research-summary.pdf", sub: "3 sources · 2 min read")))
            }
        }
    }

    func publishPost(text: String?, imageData: Data?, videoURL: String? = nil) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (trimmed?.isEmpty == false) ? trimmed : nil
        guard body != nil || imageData != nil || videoURL != nil else { return }

        let post = Post(
            author: user.handle,
            meta: "just now",
            avatarGradient: user.avatarGradient,
            avatarURL: user.avatarURL,
            imageData: imageData,
            videoURL: videoURL,
            imageAspect: imageData != nil || videoURL != nil ? 1.25 : 1.0,
            text: body,
            likeCount: 0,
            isHalfWidth: false
        )
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            posts.insert(post, at: 0)
            user.postCount += 1
        }
        schedulePersist()
    }

    func openComposer() {
        guard activeTab == .home else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            isComposing = true
            showAttachMenu = false
        }
    }

    func closeComposer() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            isComposing = false
            showAttachMenu = false
            composeText = ""
            composeAttachments = []
            editingAttachmentID = nil
            showCompose = false
        }
    }

    func removeAttachment(_ id: UUID) {
        composeAttachments.removeAll { $0.id == id }
        if editingAttachmentID == id { editingAttachmentID = nil }
    }

    func addAttachment(_ attachment: ComposeAttachment, closeMenu: Bool = true) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            composeAttachments.append(attachment)
            if closeMenu { showAttachMenu = false }
        }
    }

    func addAttachments(_ attachments: [ComposeAttachment]) {
        guard !attachments.isEmpty else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            composeAttachments.append(contentsOf: attachments)
            showAttachMenu = false
        }
    }

    func updateAttachment(_ id: UUID, mutate: (inout ComposeAttachment) -> Void) {
        guard let i = composeAttachments.firstIndex(where: { $0.id == id }) else { return }
        mutate(&composeAttachments[i])
    }

    func openMediaEditor(_ id: UUID) {
        editingAttachmentID = id
    }

    func closeMediaEditor() {
        editingAttachmentID = nil
    }

    var editingAttachment: ComposeAttachment? {
        guard let id = editingAttachmentID else { return nil }
        return composeAttachments.first(where: { $0.id == id })
    }

    var canSendCompose: Bool {
        !composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !composeAttachments.isEmpty
    }

    func publishCompose() {
        guard canSendCompose else { return }
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let caption = text.isEmpty ? nil : text

        if composeAttachments.isEmpty {
            publishPost(text: caption, imageData: nil)
        } else {
            var placedCaption = false
            for att in composeAttachments {
                switch att.kind {
                case .textOnly:
                    break
                case .audio:
                    let captionText = caption ?? "🎙 Voice note · \(att.durationLabel ?? "0:00")"
                    publishPost(text: placedCaption ? nil : captionText, imageData: att.imageData)
                    placedCaption = true
                case .photo:
                    publishPost(
                        text: placedCaption ? nil : caption,
                        imageData: att.imageData,
                        videoURL: Self.persistedVideoURL(from: att.videoURL)
                    )
                    placedCaption = true
                case .short:
                    withAnimation {
                        shorts.insert(
                            Short(channel: user.handle, subscribers: "you · just now",
                                  caption: caption ?? "New short",
                                  gradient: user.avatarGradient,
                                  imageData: att.imageData,
                                  videoURL: Self.persistedVideoURL(from: att.videoURL),
                                  likeCount: 0),
                            at: 0)
                    }
                    activeTab = .watch
                    watchSubFeed = .shorts
                case .longForm:
                    withAnimation {
                        videos.insert(
                            VideoItem(title: caption ?? "Untitled video",
                                      channel: user.handle,
                                      meta: "\(user.handle) · just now",
                                      duration: att.durationLabel ?? "0:08",
                                      thumbGradient: user.avatarGradient,
                                      thumbData: att.imageData,
                                      videoURL: Self.persistedVideoURL(from: att.videoURL),
                                      likes: 0),
                            at: 0)
                    }
                    activeTab = .watch
                    watchSubFeed = .feed
                }
            }
        }
        closeComposer()
        persistSession()
    }

    /// Copies picker temp movies into Application Support so they survive rebuilds.
    private static func persistedVideoURL(from source: URL?) -> String? {
        VideoLibrary.persist(source)
    }

    func addStory(imageData: Data) {
        let frame = StoryFrame(imageData: imageData, seen: false)
        if let i = stories.firstIndex(where: \.isYou) {
            stories[i].frames.insert(frame, at: 0)
        } else {
            stories.insert(
                Story(name: "You", letter: String(user.name.prefix(1)),
                      gradient: user.avatarGradient,
                      frames: [frame],
                      isYou: true),
                at: 0)
        }
        schedulePersist()
    }

    func openOwnProfile() {
        profileUser = .own(from: user, posts: myPosts.count)
        showProfile = true
    }

    func openUserProfile(handle: String, name: String? = nil,
                         avatarURL: String? = nil, avatarGradient: [Color]? = nil) {
        let cleaned = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        if cleaned.lowercased() == user.handle.lowercased() {
            openOwnProfile()
            return
        }
        let authorPosts = posts.filter {
            $0.author == cleaned || $0.author == "@\(cleaned)"
        }
        let sample = authorPosts.first
        profileUser = ProfileUser(
            name: name ?? cleaned,
            handle: cleaned,
            avatarURL: avatarURL ?? sample?.avatarURL,
            avatarGradient: avatarGradient ?? sample?.avatarGradient ?? SampleData.g1,
            bio: "On gojogo.",
            category: "Creator",
            postCount: max(authorPosts.count, 1),
            followerCount: Int.random(in: 800...180_000),
            followingCount: Int.random(in: 40...900),
            isOwn: false,
            following: sample?.following ?? false
        )
        showProfile = true
    }

    func closeProfile() {
        showProfile = false
        profileUser = nil
    }

    func toggleProfileFollow() {
        guard var p = profileUser, !p.isOwn else { return }
        p.following.toggle()
        p.followerCount += p.following ? 1 : -1
        profileUser = p
        // Mirror onto feed posts with same author when present.
        for i in posts.indices where posts[i].author == p.handle || posts[i].author == "@\(p.handle)" {
            posts[i].following = p.following
        }
        schedulePersist()
    }

    func openStory(_ story: Story, at frame: Int = 0) {
        guard story.hasMedia else { return }
        let start = min(max(frame, 0), max(story.frames.count - 1, 0))
        let preferred: Int = {
            if let unseen = story.frames.firstIndex(where: { !$0.seen }) { return unseen }
            return start
        }()
        storyViewerRail = storyTray.filter(\.hasMedia).map(\.id)
        viewingFrameIndex = preferred
        viewingStory = stories.first(where: { $0.id == story.id }) ?? story
        // Overlay on Home avoids fullScreenCover fight with swipe-down.
        storyOverlayActive = !showStoriesBrowser
    }

    func closeStoryViewer() {
        viewingStory = nil
        viewingFrameIndex = 0
        storyViewerRail = []
        storyOverlayActive = false
        stories = storyTray
        schedulePersist()
    }

    func markFrameSeen(storyID: UUID, frameID: UUID) {
        guard let si = stories.firstIndex(where: { $0.id == storyID }),
              let fi = stories[si].frames.firstIndex(where: { $0.id == frameID }) else { return }
        stories[si].frames[fi].seen = true
        if viewingStory?.id == storyID {
            viewingStory = stories[si]
        }
        schedulePersist()
    }

    private func liveStory(id: UUID) -> Story? {
        stories.first(where: { $0.id == id })
    }

    /// Advance within the person, then to the next person. Returns false if finished.
    @discardableResult
    func advanceStory() -> Bool {
        guard let current = viewingStory,
              let live = liveStory(id: current.id) else {
            closeStoryViewer(); return false
        }
        if viewingFrameIndex + 1 < live.frames.count {
            viewingFrameIndex += 1
            viewingStory = live
            return true
        }
        guard let authorIndex = storyViewerRail.firstIndex(of: current.id),
              authorIndex + 1 < storyViewerRail.count,
              let next = liveStory(id: storyViewerRail[authorIndex + 1]) else {
            closeStoryViewer()
            return false
        }
        viewingFrameIndex = 0
        viewingStory = next
        return true
    }

    /// Go back within the person, then to the previous person.
    @discardableResult
    func retreatStory() -> Bool {
        guard let current = viewingStory,
              let live = liveStory(id: current.id) else {
            closeStoryViewer(); return false
        }
        if viewingFrameIndex > 0 {
            viewingFrameIndex -= 1
            viewingStory = live
            return true
        }
        guard let authorIndex = storyViewerRail.firstIndex(of: current.id),
              authorIndex > 0,
              let prev = liveStory(id: storyViewerRail[authorIndex - 1]) else {
            return false
        }
        viewingFrameIndex = max(prev.frames.count - 1, 0)
        viewingStory = prev
        return true
    }

    func jumpToAdjacentAuthor(forward: Bool) {
        guard let current = viewingStory,
              let authorIndex = storyViewerRail.firstIndex(of: current.id) else { return }
        if forward {
            guard authorIndex + 1 < storyViewerRail.count,
                  let next = liveStory(id: storyViewerRail[authorIndex + 1]) else {
                closeStoryViewer()
                return
            }
            viewingFrameIndex = 0
            viewingStory = next
        } else if authorIndex > 0,
                  let prev = liveStory(id: storyViewerRail[authorIndex - 1]) {
            viewingFrameIndex = 0
            viewingStory = prev
        }
    }

    // MARK: Videos / Shorts

    func toggleVideoLike(_ id: UUID) {
        guard let i = videos.firstIndex(where: { $0.id == id }) else { return }
        videos[i].liked.toggle()
        videos[i].likes += videos[i].liked ? 1 : -1
        schedulePersist()
    }

    func toggleVideoSave(_ id: UUID) {
        guard let i = videos.firstIndex(where: { $0.id == id }) else { return }
        videos[i].saved.toggle()
        schedulePersist()
    }

    func toggleShortLike(_ id: UUID) {
        guard let i = shorts.firstIndex(where: { $0.id == id }) else { return }
        shorts[i].liked.toggle()
        shorts[i].likeCount += shorts[i].liked ? 1 : -1
        schedulePersist()
    }

    /// Like only (double-tap) — no-ops if already liked. Returns whether newly liked.
    @discardableResult
    func likeShort(_ id: UUID) -> Bool {
        guard let i = shorts.firstIndex(where: { $0.id == id }) else { return false }
        guard !shorts[i].liked else { return false }
        shorts[i].liked = true
        shorts[i].likeCount += 1
        schedulePersist()
        return true
    }

    func toggleShortBookmark(_ id: UUID) {
        guard let i = shorts.firstIndex(where: { $0.id == id }) else { return }
        shorts[i].bookmarked.toggle()
        schedulePersist()
    }

    func toggleShortFollow(_ id: UUID) {
        guard let i = shorts.firstIndex(where: { $0.id == id }) else { return }
        shorts[i].following.toggle()
        schedulePersist()
    }

    // MARK: Economy / people

    var savedProducts: [Product] {
        ([featuredProduct] + products).filter(\.saved)
    }

    func liveProduct(id: UUID) -> Product? {
        if featuredProduct.id == id { return featuredProduct }
        return products.first(where: { $0.id == id })
    }

    func openProduct(_ product: Product) {
        browsingProduct = liveProduct(id: product.id) ?? product
    }

    func closeProduct() {
        browsingProduct = nil
    }

    func openSellerChat(for product: Product) {
        messagingProduct = liveProduct(id: product.id) ?? product
        if sellerChat.isEmpty {
            sellerChat = [
                ChatMessage(text: "Hey — is \(product.name) still available?", fromUser: true),
                ChatMessage(
                    text: "Yes. I can meet near \(product.distance) · usually free after 6.",
                    fromUser: false),
            ]
        }
        sellerDraft = ""
    }

    func closeSellerChat() {
        messagingProduct = nil
        sellerDraft = ""
    }

    func sendSellerMessage() {
        let text = sellerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, messagingProduct != nil else { return }
        sellerChat.append(ChatMessage(text: text, fromUser: true))
        sellerDraft = ""
        let replies = [
            "Sounds good — I can hold it until tomorrow.",
            "Cash or transfer both work.",
            "Want a couple more photos?",
        ]
        let reply = replies.randomElement() ?? "Got it."
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            self?.sellerChat.append(ChatMessage(text: reply, fromUser: false))
            self?.schedulePersist()
        }
        schedulePersist()
    }

    func toggleSaveProduct(_ id: UUID) {
        if featuredProduct.id == id {
            featuredProduct.saved.toggle()
            if browsingProduct?.id == id { browsingProduct?.saved = featuredProduct.saved }
            schedulePersist()
            return
        }
        guard let i = products.firstIndex(where: { $0.id == id }) else { return }
        products[i].saved.toggle()
        if browsingProduct?.id == id { browsingProduct?.saved = products[i].saved }
        schedulePersist()
    }

    // MARK: GojoTV

    func openTVShow(_ id: UUID?) {
        guard let id else {
            selectedTVShow = tvHero
            return
        }
        if tvHero.id == id {
            selectedTVShow = tvHero
            return
        }
        selectedTVShow = tvShows.first(where: { $0.id == id })
    }

    func closeTVShow() {
        selectedTVShow = nil
    }

    func toggleTVWatchlist(_ id: UUID) {
        if tvHero.id == id {
            tvHero.onWatchlist.toggle()
            if selectedTVShow?.id == id { selectedTVShow?.onWatchlist = tvHero.onWatchlist }
            schedulePersist()
            return
        }
        guard let i = tvShows.firstIndex(where: { $0.id == id }) else { return }
        tvShows[i].onWatchlist.toggle()
        if selectedTVShow?.id == id { selectedTVShow?.onWatchlist = tvShows[i].onWatchlist }
        schedulePersist()
    }

    func playTVShow(_ show: TVShow) {
        let key = String(show.title.prefix(10)).lowercased()
        let match = videos.first(where: { $0.title.lowercased().contains(key) || key.contains(String($0.title.prefix(8)).lowercased()) })
        playVideo((match ?? videos.first)?.id ?? UUID())
    }

    func toggleFollowPerson(_ id: UUID) {
        guard let i = people.firstIndex(where: { $0.id == id }) else { return }
        people[i].following.toggle()
        user.followingCount += people[i].following ? 1 : -1
        schedulePersist()
    }

    // MARK: GojoTravel

    var filteredTravelPlaces: [TravelPlace] {
        let q = travelQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pool = SampleData.travelSuggestions + travelRecent
        guard !q.isEmpty else { return pool }
        return pool.filter {
            $0.name.lowercased().contains(q) || $0.subtitle.lowercased().contains(q)
        }
    }

    func openTravelSearch() {
        travelQuery = ""
        withAnimation(.easeInOut(duration: 0.28)) { travelPhase = .searching }
    }

    func closeTravelSearch() {
        travelQuery = ""
        withAnimation(.easeInOut(duration: 0.28)) { travelPhase = .home }
    }

    func selectTravelDestination(_ place: TravelPlace) {
        travelDropoff = place
        travelRideOptions = SampleData.rideOptions(to: place)
        selectedRide = travelRideOptions.first
        if !travelRecent.contains(where: { $0.name == place.name }) {
            travelRecent.insert(place, at: 0)
            if travelRecent.count > 8 { travelRecent = Array(travelRecent.prefix(8)) }
        }
        travelQuery = ""
        withAnimation(.easeInOut(duration: 0.32)) { travelPhase = .choosingRide }
    }

    func backFromRideChoice() {
        selectedRide = nil
        travelRideOptions = []
        withAnimation(.easeInOut(duration: 0.28)) { travelPhase = .searching }
    }

    func confirmTravelRide() {
        guard selectedRide != nil, travelDropoff != nil else { return }
        travelDriver = nil
        travelRating = 0
        withAnimation(.easeInOut(duration: 0.3)) { travelPhase = .matching }
        travelMatchTask?.cancel()
        travelMatchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            let eta = selectedRide?.etaMinutes ?? 4
            travelDriver = SampleData.sampleDriver(near: travelPickup, eta: max(2, eta / 2))
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                travelPhase = .enRoute
            }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { travelPhase = .inTrip }
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            guard !Task.isCancelled else { return }
            completeTravelTrip()
        }
    }

    func startTravelTrip() {
        withAnimation(.easeInOut(duration: 0.3)) { travelPhase = .inTrip }
    }

    func completeTravelTrip() {
        travelMatchTask?.cancel()
        withAnimation(.easeInOut(duration: 0.35)) { travelPhase = .completed }
    }

    func cancelTravelRide() {
        travelMatchTask?.cancel()
        travelDriver = nil
        selectedRide = nil
        travelRideOptions = []
        travelDropoff = nil
        travelRating = 0
        withAnimation(.easeInOut(duration: 0.3)) { travelPhase = .home }
    }

    func finishTravelTrip() {
        travelMatchTask?.cancel()
        travelDriver = nil
        selectedRide = nil
        travelRideOptions = []
        travelDropoff = nil
        travelRating = 0
        withAnimation(.easeInOut(duration: 0.3)) { travelPhase = .home }
    }

    func updateTravelPickup(latitude: Double, longitude: Double, label: String? = nil) {
        travelPickup = TravelPlace(
            id: travelPickup.id,
            name: label ?? travelPickup.name,
            subtitle: travelPickup.subtitle,
            latitude: latitude,
            longitude: longitude,
            icon: "location.fill"
        )
    }

    // MARK: Madeleine chat

    func sendMadeleine(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chatMessages.append(ChatMessage(text: trimmed, fromUser: true))
        let reply: String
        let lower = trimmed.lowercased()
        if lower.contains("feed") {
            reply = "Your feed has \(posts.count) posts. Top liked: \(posts.map(\.likeCount).max() ?? 0) likes."
        } else if lower.contains("weekend") || lower.contains("plan") {
            reply = "Saturday: football meetup near you. Sunday: night market walk — want me to pin both?"
        } else if lower.contains("football") || lower.contains("group") {
            reply = "Found 3 open football groups within 4 km. Want invites?"
        } else {
            reply = "Got it. I'll keep an eye on that — anything else?"
        }
        schedulePersist()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            self?.chatMessages.append(ChatMessage(text: reply, fromUser: false))
            self?.schedulePersist()
        }
    }
}
