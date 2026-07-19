import SwiftUI
import UIKit
import CoreLocation

@MainActor
final class AppState: ObservableObject {
    // Auth / onboarding
    @Published var phase: AuthPhase = .welcome
    @Published var onboardingStep: Int = 1
    @Published var email: String = ""

    // Appearance
    @Published var appTheme: AppTheme = .dark

    // Main navigation
    @Published var navMode: AppNavMode = .collections
    @Published var activeTab: AppTab = .home
    /// Collections dock: false = compact pill with just the active section, true = full tab row.
    @Published var navBarExpanded: Bool = false
    @Published var watchSubFeed: WatchSubFeed = .feed
    @Published var myWorldTab: MyWorldTab = .messages
    @Published var selectedWorldConversationID: UUID? = nil
    @Published var worldDraft: String = ""
    @Published var worldSearch: String = ""
    @Published var worldContacts: [WorldContact] = SampleData.worldContacts
    @Published var worldCircles: [WorldCircle] = SampleData.worldCircles
    @Published var worldConversations: [WorldConversation] = SampleData.worldConversations
    @Published var showWorldAppsMenu: Bool = false
    @Published var showWorldContact: Bool = false
    @Published var worldIsEditing: Bool = false
    @Published var worldSharingLocation: Bool = true
    @Published var showWorldFilters: Bool = false
    /// Single modal-sheet slot for My World (new message / poll / send-later).
    @Published var worldSheet: WorldSheetKind? = nil
    @Published var worldFilterUnreadOnly: Bool = false
    /// Media staged in the chat composer, sent together with the next message.
    @Published var worldPendingAttachments: [WorldPendingAttachment] = []
    /// Conversation currently showing the "…" typing indicator.
    @Published var worldTypingConversationID: UUID? = nil
    private var worldReplyTasks: [UUID: Task<Void, Never>] = [:]
    /// Message the tapback/action overlay is focused on (long-press target).
    @Published var worldReactionTarget: UUID? = nil
    /// Message the composer is currently quoting as an inline reply.
    @Published var worldReplyingTo: UUID? = nil
    /// In-view overlays shown over the immersive chat (sheets don't present there).
    @Published var showWorldPollOverlay: Bool = false
    @Published var showWorldSendLaterOverlay: Bool = false
    /// Chosen date for a Send-Later message.
    @Published var worldSendLaterDate: Date = Calendar.current.date(
        byAdding: .day, value: 1, to: Date()) ?? Date()
    /// When set, the next send is scheduled for this label instead of sent now.
    @Published var worldSendLaterLabel: String? = nil
    private var worldScheduledTasks: [UUID: Task<Void, Never>] = [:]
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

    // Activity / notifications
    @Published var notifications: [ActivityItem] = SampleData.notifications
    @Published var showActivity: Bool = false

    // Direct messages (per-handle threads)
    @Published var dmPeer: ProfileUser? = nil
    @Published var dmDraft: String = ""
    @Published var dmThreads: [String: [ChatMessage]] = [:]

    // Channel subscriptions + video reactions
    @Published var subscribedChannels: Set<String> = []
    @Published var dislikedVideoIDs: Set<UUID> = []
    @Published var downloadedVideoIDs: Set<UUID> = []
    /// Profiles the user turned notifications on for.
    @Published var notifyHandles: Set<String> = []

    // Profile editing + post viewer (profile grid)
    @Published var showEditProfile: Bool = false
    @Published var viewingPostID: UUID? = nil

    // Profile Home (customizable canvas tab)
    @Published var profileHomeBlocks: [ProfileHomeBlock] = []
    @Published var profileHomeEditing: Bool = false
    /// Non-nil while a block editor sheet is presented.
    @Published var editingHomeBlockID: UUID? = nil
    /// Drives the "add a block" type-picker sheet.
    @Published var showHomeBlockPicker: Bool = false

    // User + content (live, mutable)
    @Published var user = GGUser()
    @Published var interests: [Interest] = SampleData.interests
    @Published var stories: [Story] = SampleData.stories
    @Published var posts: [Post] = SampleData.posts
    @Published var videos: [VideoItem] = SampleData.videos
    @Published var shorts: [Short] = SampleData.shorts
    /// Home-feed video mute — shared across every post until toggled again.
    @Published var feedVideosMuted: Bool = true
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

    // GojoDelivery
    @Published var deliveryRestaurants: [DeliveryRestaurant] = SampleData.deliveryRestaurants
    @Published var selectedDeliveryRestaurantID: UUID? = nil
    @Published var deliverySearch: String = ""
    @Published var deliveryCategory: String = "All"
    @Published var deliveryCart: [DeliveryCartLine] = []
    @Published var deliveryCartRestaurantID: UUID? = nil
    @Published var showDeliveryCheckout: Bool = false
    @Published var deliveryStatus: DeliveryOrderStatus? = nil
    @Published var deliveryCourier: DeliveryCourier? = nil
    @Published var deliveryEtaMinutes: Int = 0
    /// 0 = courier at restaurant, 1 = courier at your door.
    @Published var deliveryCourierProgress: Double = 0
    @Published var deliveryRating: Int = 0
    @Published var deliveryPastOrders: [DeliveryPastOrder] = []
    /// Restaurant the active order was placed from (kept after cart clears).
    @Published var deliveryOrderRestaurantID: UUID? = nil
    @Published var deliveryOrderTotalLabel: String = ""
    @Published var deliveryOrderSummary: String = ""
    private var deliveryTask: Task<Void, Never>?

    // Partner (Become a driver / delivery partner)
    /// Roles the user has fully onboarded into (can go online).
    @Published var partnerRoles: Set<PartnerRole> = []
    /// Non-nil while the become-a-partner flow is presented.
    @Published var partnerOnboardingRole: PartnerRole? = nil
    @Published var partnerStep: PartnerOnboardingStep = .rules
    @Published var partnerApplication = PartnerApplication(role: .driver)
    @Published var partnerAgreedToTerms: Bool = false
    @Published var partnerStakeProcessing: Bool = false
    /// Non-nil while the partner dashboard (working UI) is presented.
    @Published var partnerDashboardRole: PartnerRole? = nil
    @Published var partnerOnline: Bool = false
    @Published var partnerJobPhase: PartnerJobPhase = .idle
    @Published var partnerJob: PartnerJob? = nil
    @Published var partnerJobProgress: Double = 0
    // Earnings / trips / rating are tracked independently per role (driver vs courier).
    @Published var partnerEarningsByRole: [String: Double] = [:]
    @Published var partnerJobsByRole: [String: Int] = [:]
    @Published var partnerRatingByRole: [String: Double] = [:]
    private var partnerOfferTask: Task<Void, Never>?
    private var partnerJobTask: Task<Void, Never>?

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
            case "delivery": return .delivery
            case "economy": return .economy
            case "search": return .search
            default: return .home
            }
        }()
        watchSubFeed = WatchSubFeed(rawValue: cached.watchSubFeedRaw) ?? .feed
        if let raw = cached.navModeRaw, let mode = AppNavMode(rawValue: raw) {
            navMode = mode
        }
        if let raw = cached.appThemeRaw, let theme = AppTheme(rawValue: raw) {
            appTheme = theme
        }
        subscribedChannels = Set(cached.subscribedChannels ?? [])
        dislikedVideoIDs = Set(cached.dislikedVideoIDs ?? [])
        downloadedVideoIDs = Set(cached.downloadedVideoIDs ?? [])
        notifyHandles = Set(cached.notifyHandles ?? [])
        partnerRoles = Set((cached.partnerRoles ?? []).compactMap { PartnerRole(rawValue: $0) })
        partnerEarningsByRole = cached.partnerEarningsByRole ?? [:]
        partnerJobsByRole = cached.partnerJobsByRole ?? [:]
        profileHomeBlocks = cached.profileHomeBlocks ?? []
        dmThreads = (cached.dmThreads ?? [:]).mapValues { $0.map { $0.asDomain() } }
        phase = .app
        onboardingStep = 3
        topUpSeedContent()
        refreshSampleMediaFromSeed()
        // Rewrite durable relative video refs after migration.
        schedulePersist()
    }

    /// Older cached sessions predate newer seed content — append anything they're missing
    /// (matched by stable content keys, since seed UUIDs change per launch).
    private func topUpSeedContent() {
        let postKeys = Set(posts.map { "\($0.author)|\($0.text ?? "")" })
        for p in SampleData.posts where !postKeys.contains("\(p.author)|\(p.text ?? "")") {
            posts.append(p)
            commentsByPost[p.id] = SampleData.defaultComments
        }
        let videoKeys = Set(videos.map(\.title))
        for v in SampleData.videos where !videoKeys.contains(v.title) {
            videos.append(v)
        }
        let shortKeys = Set(shorts.map(\.caption))
        for s in SampleData.shorts where !shortKeys.contains(s.caption) {
            shorts.append(s)
        }
        let productKeys = Set(products.map(\.name) + [featuredProduct.name])
        for p in SampleData.products where !productKeys.contains(p.name) {
            products.append(p)
        }
        let peopleKeys = Set(people.map(\.name))
        for p in SampleData.people where !peopleKeys.contains(p.name) {
            people.append(p)
        }
        let storyKeys = Set(stories.map(\.name))
        for s in SampleData.stories where !storyKeys.contains(s.name) {
            stories.append(s)
        }
    }

    /// Swap placeholder picsum URLs on seed content for the bundled sample assets.
    private func refreshSampleMediaFromSeed() {
        let seedByKey = Dictionary(
            SampleData.posts.map { ("\($0.author)|\($0.text ?? "")", $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for i in posts.indices {
            let key = "\(posts[i].author)|\(posts[i].text ?? "")"
            if let seed = seedByKey[key] {
                posts[i].imageURL = seed.imageURL
                posts[i].avatarURL = seed.avatarURL
                posts[i].mediaItems = seed.mediaItems
                posts[i].imageAspect = seed.imageAspect
                posts[i].videoURL = seed.videoURL
            } else if let url = posts[i].imageURL, url.contains("picsum.photos") {
                let pick = SampleData.allSampleMedia[abs(key.hashValue) % SampleData.allSampleMedia.count]
                posts[i].imageURL = pick
            }
            if let avatar = posts[i].avatarURL, avatar.contains("picsum.photos") {
                posts[i].avatarURL = SampleData.allSampleMedia[
                    abs(posts[i].author.hashValue) % SampleData.allSampleMedia.count
                ]
            }
            if let v = posts[i].videoURL, v.hasPrefix("http") {
                posts[i].videoURL = SampleData.repairedVideoURL(v)
            }
            for j in posts[i].mediaItems.indices {
                if let u = posts[i].mediaItems[j].imageURL, u.contains("picsum.photos") {
                    posts[i].mediaItems[j].imageURL = SampleData.allSampleMedia[
                        (i + j) % SampleData.allSampleMedia.count
                    ]
                }
                if let v = posts[i].mediaItems[j].videoURL, v.hasPrefix("http") {
                    posts[i].mediaItems[j].videoURL = SampleData.repairedVideoURL(v)
                }
            }
        }

        let storySeed = Dictionary(uniqueKeysWithValues: SampleData.stories.map { ($0.name, $0) })
        for i in stories.indices {
            guard let seed = storySeed[stories[i].name], !seed.frames.isEmpty else { continue }
            stories[i].frames = seed.frames
        }

        let shortSeed = Dictionary(uniqueKeysWithValues: SampleData.shorts.map { ($0.caption, $0) })
        for i in shorts.indices {
            if let seed = shortSeed[shorts[i].caption] {
                shorts[i].imageURL = seed.imageURL
                shorts[i].videoURL = seed.videoURL
            } else if let u = shorts[i].imageURL, u.contains("picsum.photos") {
                shorts[i].imageURL = SampleData.allSampleMedia[i % SampleData.allSampleMedia.count]
            }
            if let v = shorts[i].videoURL, v.hasPrefix("http") {
                shorts[i].videoURL = SampleData.repairedVideoURL(v)
            }
        }

        let videoSeed = Dictionary(uniqueKeysWithValues: SampleData.videos.map { ($0.title, $0) })
        for i in videos.indices {
            if let seed = videoSeed[videos[i].title] {
                videos[i].thumbURL = seed.thumbURL
                videos[i].videoURL = seed.videoURL
            } else if let u = videos[i].thumbURL, u.contains("picsum.photos") {
                videos[i].thumbURL = SampleData.allSampleMedia[i % SampleData.allSampleMedia.count]
            }
            if let v = videos[i].videoURL, v.hasPrefix("http") {
                videos[i].videoURL = SampleData.repairedVideoURL(v)
            }
        }

        let productSeed = Dictionary(
            uniqueKeysWithValues: (SampleData.products + [SampleData.featuredProduct]).map { ($0.name, $0) }
        )
        if let seed = productSeed[featuredProduct.name] {
            featuredProduct.imageURL = seed.imageURL
        }
        for i in products.indices {
            if let seed = productSeed[products[i].name] {
                products[i].imageURL = seed.imageURL
            } else if let u = products[i].imageURL, u.contains("picsum.photos") {
                products[i].imageURL = SampleData.allSampleMedia[i % SampleData.allSampleMedia.count]
            }
        }
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

    var viewingPost: Post? {
        guard let id = viewingPostID else { return nil }
        return posts.first(where: { $0.id == id })
    }

    func openPostViewer(_ id: UUID) { viewingPostID = id }
    func closePostViewer() { viewingPostID = nil }

    // MARK: Appearance

    func toggleTheme() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.3)) {
            appTheme = appTheme == .dark ? .light : .dark
        }
        schedulePersist()
    }

    // MARK: Nav mode (My World ↔ Collections)

    func enterMyWorld() {
        closeComposer()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            navMode = .myWorld
            navBarExpanded = false
        }
        schedulePersist()
    }

    func enterCollections() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            navMode = .collections
        }
        schedulePersist()
    }

    func openWorldConversation(_ id: UUID) {
        showWorldAppsMenu = false
        showWorldContact = false
        showWorldFilters = false
        selectedWorldConversationID = id
        if let i = worldConversations.firstIndex(where: { $0.id == id }) {
            worldConversations[i].unread = 0
        }
    }

    func closeWorldConversation() {
        selectedWorldConversationID = nil
        worldDraft = ""
        worldPendingAttachments = []
        showWorldAppsMenu = false
        showWorldContact = false
        worldReactionTarget = nil
        worldReplyingTo = nil
        worldSendLaterLabel = nil
        worldSheet = nil
        showWorldPollOverlay = false
        showWorldSendLaterOverlay = false
    }

    var worldUnreadCount: Int {
        worldConversations.reduce(0) { $0 + $1.unread }
    }

    var selectedWorldConversation: WorldConversation? {
        guard let id = selectedWorldConversationID else { return nil }
        return worldConversations.first(where: { $0.id == id })
    }

    var selectedWorldContact: WorldContact? {
        guard let convo = selectedWorldConversation,
              let cid = convo.contactID else { return nil }
        return worldContacts.first(where: { $0.id == cid })
    }

    /// Full-screen My World surfaces that hide the mode tab bar (chat / contact).
    var isWorldImmersive: Bool {
        navMode == .myWorld && (selectedWorldConversationID != nil || showWorldContact)
    }

    // MARK: My World — list filtering

    /// Conversations matching the search field + unread filter.
    /// Pinned first, then most recently active (send or receive).
    var worldFilteredConversations: [WorldConversation] {
        var list = worldConversations
        if worldFilterUnreadOnly { list = list.filter { $0.unread > 0 } }
        let q = worldSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.title.lowercased().contains(q)
                    || $0.preview.lowercased().contains(q)
                    || $0.messages.contains { $0.kind == .text && $0.text.lowercased().contains(q) }
            }
        }
        return list.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned && !b.pinned }
            return a.lastActivityAt > b.lastActivityAt
        }
    }

    var worldPinnedConversations: [WorldConversation] {
        worldFilteredConversations.filter(\.pinned)
    }

    var worldUnpinnedConversations: [WorldConversation] {
        worldFilteredConversations.filter { !$0.pinned }
    }

    // MARK: My World — conversation management

    func togglePinWorldConversation(_ id: UUID) {
        guard let i = worldConversations.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            worldConversations[i].pinned.toggle()
        }
    }

    func toggleUnreadWorldConversation(_ id: UUID) {
        guard let i = worldConversations.firstIndex(where: { $0.id == id }) else { return }
        worldConversations[i].unread = worldConversations[i].unread > 0 ? 0 : 1
    }

    func deleteWorldConversation(_ id: UUID) {
        worldReplyTasks[id]?.cancel()
        worldReplyTasks[id] = nil
        if worldTypingConversationID == id { worldTypingConversationID = nil }
        if selectedWorldConversationID == id { closeWorldConversation() }
        withAnimation(.easeOut(duration: 0.25)) {
            worldConversations.removeAll { $0.id == id }
        }
    }

    /// Opens the existing 1:1 thread for a contact, creating it if needed.
    /// Always lands the thread in the main Messages list (unpinned, most recent).
    func startWorldConversation(with contact: WorldContact) {
        worldSheet = nil
        showWorldFilters = false
        worldFilterUnreadOnly = false
        worldSearch = ""

        if let i = worldConversations.firstIndex(where: { $0.contactID == contact.id }) {
            worldConversations[i].pinned = false
            worldConversations[i].title = contact.name
            worldConversations[i].avatarURL = contact.avatarURL
            worldConversations[i].avatarGradient = contact.avatarGradient
            bumpWorldConversationActivity(at: i)
            // Move to front of the array so the list update is obvious.
            let convo = worldConversations.remove(at: i)
            worldConversations.insert(convo, at: 0)
            openWorldConversation(convo.id)
            return
        }

        let convo = WorldConversation(
            contactID: contact.id, title: contact.name,
            preview: "Say hi 👋", timeAgo: "now",
            avatarURL: contact.avatarURL, avatarGradient: contact.avatarGradient,
            messages: [WorldMessage(kind: .timestamp, text: "Today")],
            lastActivityAt: Date()
        )
        worldConversations.insert(convo, at: 0)
        openWorldConversation(convo.id)
    }

    /// Adds a contact reached by phone number or username, then opens the thread.
    func addWorldContact(_ raw: String) {
        let entry = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty else { return }
        let isPhone = entry.allSatisfy { "+0123456789 -()".contains($0) }
        let cleaned = entry.hasPrefix("@") ? String(entry.dropFirst()) : entry
        let contact = WorldContact(
            name: isPhone ? entry : cleaned.capitalized,
            username: isPhone ? cleaned.filter(\.isNumber) : cleaned.lowercased(),
            phone: isPhone ? entry : ""
        )
        worldContacts.append(contact)
        startWorldConversation(with: contact)
    }

    /// Opens the group thread for a circle, creating it if needed — always visible in Messages.
    func openWorldCircle(_ circle: WorldCircle) {
        if let existing = worldConversations.first(where: { $0.circleID == circle.id }) {
            if let i = worldConversations.firstIndex(where: { $0.id == existing.id }) {
                // Ensure it surfaces in the list (unpin so it shows in the main msgs rows).
                if worldConversations[i].pinned {
                    worldConversations[i].pinned = false
                }
                bumpWorldConversationActivity(at: i)
            }
            openWorldConversation(existing.id)
            return
        }
        let members = worldContacts.filter { circle.memberIDs.contains($0.id) }
        let preview = members.isEmpty
            ? "New circle"
            : members.prefix(3).map { $0.name.components(separatedBy: " ").first ?? $0.name }.joined(separator: ", ")
        let convo = WorldConversation(
            circleID: circle.id, title: circle.name,
            preview: preview, timeAgo: "now", isGroup: true,
            messages: [
                WorldMessage(kind: .timestamp, text: "Today"),
                WorldMessage(kind: .system, text: "You created \(circle.name)")
            ],
            lastActivityAt: Date()
        )
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            worldConversations.insert(convo, at: 0)
        }
        openWorldConversation(convo.id)
    }

    // MARK: My World — sending

    func sendWorldMessage() {
        let text = worldDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = worldPendingAttachments
        guard !text.isEmpty || !attachments.isEmpty else { return }

        if attachments.count >= 2 {
            let items = attachments.map {
                WorldCarouselItem(imageData: $0.imageData, isVideo: $0.isVideo,
                                  durationLabel: $0.durationLabel)
            }
            let hasVideo = attachments.contains(where: \.isVideo)
            let preview = hasVideo
                ? "You: 🖼 \(attachments.count) items"
                : "You: 🖼 \(attachments.count) photos"
            deliverWorldMessage(
                WorldMessage(kind: .carousel, text: "", fromUser: true,
                             readLabel: "Delivered",
                             imageData: attachments.first?.imageData,
                             carouselItems: items),
                preview: preview)
            worldPendingAttachments = []
        } else if let att = attachments.first {
            deliverWorldMessage(
                WorldMessage(kind: att.isVideo ? .video : .photo, text: "",
                             fromUser: true, readLabel: "Delivered",
                             imageData: att.imageData, durationLabel: att.durationLabel),
                preview: att.isVideo ? "You: 📹 Video" : "You: 📷 Photo")
            worldPendingAttachments = []
        }

        if !text.isEmpty {
            let isEmojiOnly = text.count <= 3 && text.unicodeScalars.allSatisfy { $0.properties.isEmoji }
            let scheduled = worldSendLaterLabel
            let msg = WorldMessage(kind: isEmojiOnly ? .emoji : .text, text: text,
                                   fromUser: true,
                                   readLabel: scheduled == nil ? "Delivered" : nil,
                                   replyTo: currentReplySnippet(),
                                   scheduledLabel: scheduled)
            worldDraft = ""
            clearWorldReply()
            worldSendLaterLabel = nil
            deliverWorldMessage(msg, preview: "You: \(text)", scheduled: scheduled != nil)
        }
    }

    /// Builds the quoted snippet for whatever message is being replied to.
    private func currentReplySnippet() -> WorldReplySnippet? {
        guard let rid = worldReplyingTo,
              let convo = selectedWorldConversation,
              let src = convo.messages.first(where: { $0.id == rid }) else { return nil }
        let author = src.fromUser ? "You" : (src.senderName ?? convo.title)
        return WorldReplySnippet(authorName: author,
                                 preview: src.snippetText,
                                 fromUser: src.fromUser)
    }

    func beginWorldReply(to id: UUID) {
        worldReactionTarget = nil
        withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
            worldReplyingTo = id
        }
    }

    func clearWorldReply() {
        withAnimation(.easeOut(duration: 0.18)) { worldReplyingTo = nil }
    }

    func stageWorldAttachment(_ attachment: WorldPendingAttachment) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            worldPendingAttachments.append(attachment)
        }
    }

    func removeWorldAttachment(_ id: UUID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            worldPendingAttachments.removeAll { $0.id == id }
        }
    }

    func sendWorldSticker(_ emoji: String) {
        deliverWorldMessage(
            WorldMessage(kind: .emoji, text: emoji, fromUser: true, readLabel: "Delivered"),
            preview: "You: \(emoji)")
    }

    func sendWorldPhoto(_ data: Data) {
        deliverWorldMessage(
            WorldMessage(kind: .photo, text: "", fromUser: true,
                         readLabel: "Delivered", imageData: data),
            preview: "You: 📷 Photo")
    }

    func sendWorldAudio(durationLabel: String) {
        deliverWorldMessage(
            WorldMessage(kind: .audio, text: "", fromUser: true,
                         readLabel: "Delivered", durationLabel: durationLabel),
            preview: "You: 🎤 Audio message")
    }

    func sendWorldLocation() {
        deliverWorldMessage(
            WorldMessage(kind: .location, text: "Current Location",
                         fromUser: true, readLabel: "Delivered"),
            preview: "You: 📍 Location")
    }

    /// Appends an outgoing message to the open thread and schedules the canned reply.
    /// When `scheduled` is true the bubble first appears in a pending state and is
    /// "sent" a few seconds later (demo stand-in for Send Later).
    private func deliverWorldMessage(_ msg: WorldMessage, preview: String, scheduled: Bool = false) {
        guard let id = selectedWorldConversationID,
              let i = worldConversations.firstIndex(where: { $0.id == id }) else { return }
        // Only the newest outgoing message carries a receipt label.
        if !scheduled {
            for j in worldConversations[i].messages.indices where worldConversations[i].messages[j].fromUser {
                worldConversations[i].messages[j].readLabel = nil
            }
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) {
            worldConversations[i].messages.append(msg)
            if !scheduled { worldConversations[i].preview = preview }
        }
        bumpWorldConversationActivity(at: i)
        showWorldAppsMenu = false

        if scheduled {
            scheduleWorldSendLater(messageID: msg.id, in: id, preview: preview)
        } else {
            scheduleWorldReply(for: id)
        }
    }

    /// Fires a scheduled (Send Later) message a few seconds after it's queued.
    private func scheduleWorldSendLater(messageID: UUID, in convoID: UUID, preview: String) {
        worldScheduledTasks[messageID]?.cancel()
        worldScheduledTasks[messageID] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, !Task.isCancelled,
                  let i = self.worldConversations.firstIndex(where: { $0.id == convoID }),
                  let j = self.worldConversations[i].messages.firstIndex(where: { $0.id == messageID })
            else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                for k in self.worldConversations[i].messages.indices
                where self.worldConversations[i].messages[k].fromUser {
                    self.worldConversations[i].messages[k].readLabel = nil
                }
                self.worldConversations[i].messages[j].scheduledLabel = nil
                self.worldConversations[i].messages[j].readLabel = "Delivered"
                self.worldConversations[i].preview = preview
            }
            self.bumpWorldConversationActivity(at: i)
            self.scheduleWorldReply(for: convoID)
        }
    }

    func setWorldSendLater(_ label: String?) {
        worldSendLaterLabel = label
    }

    // MARK: My World — tapbacks (reactions)

    func toggleWorldReaction(_ tapback: WorldTapback, on messageID: UUID) {
        guard let id = selectedWorldConversationID,
              let i = worldConversations.firstIndex(where: { $0.id == id }),
              let j = worldConversations[i].messages.firstIndex(where: { $0.id == messageID })
        else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) {
            var reactions = worldConversations[i].messages[j].reactions
            if let existing = reactions.firstIndex(where: { $0.fromUser && $0.tapback == tapback }) {
                reactions.remove(at: existing)          // same tapback → toggle off
            } else {
                reactions.removeAll { $0.fromUser }     // one tapback per person
                reactions.append(WorldReaction(tapback: tapback, fromUser: true))
            }
            worldConversations[i].messages[j].reactions = reactions
        }
        worldReactionTarget = nil
    }

    func copyWorldMessage(_ messageID: UUID) {
        guard let convo = selectedWorldConversation,
              let msg = convo.messages.first(where: { $0.id == messageID }) else { return }
        UIPasteboard.general.string = msg.snippetText
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        worldReactionTarget = nil
    }

    func deleteWorldMessage(_ messageID: UUID) {
        guard let id = selectedWorldConversationID,
              let i = worldConversations.firstIndex(where: { $0.id == id }) else { return }
        worldScheduledTasks[messageID]?.cancel()
        worldScheduledTasks[messageID] = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            worldConversations[i].messages.removeAll { $0.id == messageID }
        }
        worldReactionTarget = nil
    }

    // MARK: My World — polls

    func sendWorldPoll(question: String, options: [String]) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let opts = options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { WorldPollOption(text: $0) }
        guard !q.isEmpty, opts.count >= 2 else { return }
        let poll = WorldPoll(question: q, options: opts)
        showWorldPollOverlay = false
        deliverWorldMessage(
            WorldMessage(kind: .poll, text: q, fromUser: true,
                         readLabel: "Delivered", poll: poll),
            preview: "You: 📊 \(q)")
    }

    func voteWorldPoll(messageID: UUID, optionID: UUID) {
        guard let id = selectedWorldConversationID,
              let i = worldConversations.firstIndex(where: { $0.id == id }),
              let j = worldConversations[i].messages.firstIndex(where: { $0.id == messageID }),
              var poll = worldConversations[i].messages[j].poll,
              let k = poll.options.firstIndex(where: { $0.id == optionID })
        else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            if poll.options[k].voters.contains("You") {
                poll.options[k].voters.removeAll { $0 == "You" }
            } else {
                if !poll.allowsMultiple {
                    for m in poll.options.indices { poll.options[m].voters.removeAll { $0 == "You" } }
                }
                poll.options[k].voters.append("You")
            }
            worldConversations[i].messages[j].poll = poll
        }
    }

    func addWorldPollOption(messageID: UUID, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty,
              let id = selectedWorldConversationID,
              let i = worldConversations.firstIndex(where: { $0.id == id }),
              let j = worldConversations[i].messages.firstIndex(where: { $0.id == messageID }),
              var poll = worldConversations[i].messages[j].poll else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
            poll.options.append(WorldPollOption(text: t))
            worldConversations[i].messages[j].poll = poll
        }
    }

    // MARK: My World — chat background

    func setWorldBackground(_ background: WorldChatBackground) {
        guard let convo = selectedWorldConversation,
              let i = worldConversations.firstIndex(where: { $0.id == convo.id }) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.3)) {
            worldConversations[i].background = background
        }
    }

    /// Marks a thread as most recent so it floats to the top of the list.
    /// Also unpins so the thread always shows in the main Messages rows.
    private func bumpWorldConversationActivity(at index: Int) {
        guard worldConversations.indices.contains(index) else { return }
        worldConversations[index].timeAgo = "now"
        worldConversations[index].lastActivityAt = Date()
        worldConversations[index].pinned = false
    }

    private static let worldReplyPool: [String] = [
        "haha yes 😄", "omg wait really?", "love that", "on it 👌", "say less",
        "can't wait!!", "sending you something later", "lol okay okay",
        "let's do it 🔥", "miss you btw", "perfect timing", "you read my mind",
    ]

    /// Fakes the other side: typing indicator, then a reply + read receipt.
    private func scheduleWorldReply(for id: UUID) {
        worldReplyTasks[id]?.cancel()
        worldReplyTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { self.worldTypingConversationID = id }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else {
                if self.worldTypingConversationID == id { self.worldTypingConversationID = nil }
                return
            }
            self.receiveWorldReply(in: id)
        }
    }

    private func receiveWorldReply(in id: UUID) {
        if worldTypingConversationID == id { worldTypingConversationID = nil }
        guard let i = worldConversations.firstIndex(where: { $0.id == id }) else { return }
        // Mark the latest outgoing message as read.
        if let last = worldConversations[i].messages.lastIndex(where: { $0.fromUser && $0.readLabel != nil }) {
            worldConversations[i].messages[last].readLabel = "Read just now"
        }
        // Sometimes the other side tapbacks the last thing you sent, like iMessage.
        if Int.random(in: 0..<3) == 0,
           let last = worldConversations[i].messages.lastIndex(where: { $0.fromUser }),
           !worldConversations[i].messages[last].reactions.contains(where: { !$0.fromUser }) {
            let tb = WorldTapback.allCases.randomElement() ?? .heart
            withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) {
                worldConversations[i].messages[last].reactions.append(
                    WorldReaction(tapback: tb, fromUser: false))
            }
        }
        let reply = Self.worldReplyPool.randomElement() ?? "❤️"
        let members = worldCircleMembers(of: worldConversations[i])
        let sender = worldConversations[i].isGroup
            ? worldContacts.filter { members.contains($0.id) }.randomElement()?
                .name.components(separatedBy: " ").first
            : nil
        withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) {
            worldConversations[i].messages.append(
                WorldMessage(text: reply, fromUser: false, senderName: sender))
            worldConversations[i].preview = sender.map { "\($0): \(reply)" } ?? reply
            if selectedWorldConversationID != id {
                worldConversations[i].unread += 1
            }
        }
        bumpWorldConversationActivity(at: worldConversations.firstIndex(where: { $0.id == id }) ?? i)
    }

    private func worldCircleMembers(of convo: WorldConversation) -> [UUID] {
        guard let cid = convo.circleID,
              let circle = worldCircles.first(where: { $0.id == cid }) else { return [] }
        return circle.memberIDs
    }

    /// Photos exchanged in a conversation (for the contact info Photos tab).
    func worldChatPhotos(for convo: WorldConversation?) -> [Data] {
        convo?.messages.compactMap { $0.kind == .photo ? $0.imageData : nil } ?? []
    }

    func openWorldContact() {
        showWorldAppsMenu = false
        withAnimation(.easeInOut(duration: 0.28)) { showWorldContact = true }
    }

    func closeWorldContact() {
        withAnimation(.easeInOut(duration: 0.28)) { showWorldContact = false }
    }

    // MARK: Activity

    var unreadActivityCount: Int { notifications.filter { !$0.read }.count }

    func openActivity() { showActivity = true }

    func closeActivity() {
        showActivity = false
        markActivityRead()
    }

    func markActivityRead() {
        guard notifications.contains(where: { !$0.read }) else { return }
        for i in notifications.indices { notifications[i].read = true }
    }

    func pushActivity(_ item: ActivityItem) {
        notifications.insert(item, at: 0)
    }

    /// Route a tapped notification to the right surface.
    func handleActivityTap(_ item: ActivityItem) {
        showActivity = false
        switch item.kind {
        case .follow, .mention:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.openUserProfile(handle: item.actor, avatarURL: item.avatarURL)
            }
        case .like, .comment:
            if let post = myPosts.first {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.openComments(for: post.id)
                }
            }
        case .order:
            activeTab = .economy
        case .system:
            activeTab = .madeleine
        }
    }

    // MARK: Direct messages

    var dmChat: [ChatMessage] {
        guard let peer = dmPeer else { return [] }
        return dmThreads[peer.handle] ?? []
    }

    func openDirectMessage(handle: String, name: String? = nil,
                           avatarURL: String? = nil, avatarGradient: [Color]? = nil) {
        let cleaned = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        dmPeer = ProfileUser(
            name: name ?? cleaned,
            handle: cleaned,
            avatarURL: avatarURL,
            avatarGradient: avatarGradient ?? SampleData.g1,
            bio: "", category: "", postCount: 0,
            followerCount: 0, followingCount: 0,
            isOwn: false, following: false
        )
        dmDraft = ""
        if dmThreads[cleaned] == nil {
            dmThreads[cleaned] = [
                ChatMessage(text: "Hey \(user.name)! 👋", fromUser: false),
            ]
        }
    }

    func closeDirectMessage() {
        dmPeer = nil
        dmDraft = ""
    }

    func sendDirectMessage() {
        guard let peer = dmPeer else { return }
        let text = dmDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var thread = dmThreads[peer.handle] ?? []
        thread.append(ChatMessage(text: text, fromUser: true))
        dmThreads[peer.handle] = thread
        dmDraft = ""
        schedulePersist()

        let lower = text.lowercased()
        let reply: String
        if lower.contains("?") {
            reply = "Good question — let me check and get back to you tonight."
        } else if lower.contains("nice") || lower.contains("love") || lower.contains("great") {
            reply = "Appreciate it! Means a lot 🙏"
        } else if lower.contains("collab") || lower.contains("shoot") || lower.contains("project") {
            reply = "I'm in. Send me the details and let's lock a date."
        } else {
            reply = ["Haha for real.", "Yeah — was just thinking that.",
                     "Say less. 🔥", "On it. Give me a sec."].randomElement()!
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.8...1.6)) { [weak self] in
            guard let self, self.dmThreads[peer.handle] != nil else { return }
            self.dmThreads[peer.handle]?.append(ChatMessage(text: reply, fromUser: false))
            self.schedulePersist()
        }
    }

    // MARK: Channel subscriptions

    func isSubscribed(_ channel: String) -> Bool {
        subscribedChannels.contains(channel.lowercased())
    }

    func toggleSubscribe(_ channel: String) {
        let key = channel.lowercased()
        if subscribedChannels.contains(key) {
            subscribedChannels.remove(key)
            user.followingCount = max(0, user.followingCount - 1)
        } else {
            subscribedChannels.insert(key)
            user.followingCount += 1
        }
        schedulePersist()
    }

    /// Stable pseudo subscriber count per channel (prototype — no backend).
    func subscriberLabel(for channel: String) -> String {
        var hash = 0
        for u in channel.lowercased().unicodeScalars { hash = (hash &* 31 &+ Int(u.value)) }
        let base = 12_000 + abs(hash) % 2_400_000
        let total = base + (isSubscribed(channel) ? 1 : 0)
        return "\(formatCount(total)) subscribers"
    }

    // MARK: Video reactions

    func isVideoDisliked(_ id: UUID) -> Bool { dislikedVideoIDs.contains(id) }

    func toggleVideoDislike(_ id: UUID) {
        if dislikedVideoIDs.contains(id) {
            dislikedVideoIDs.remove(id)
        } else {
            dislikedVideoIDs.insert(id)
            // Disliking clears a like, YouTube-style.
            if let i = videos.firstIndex(where: { $0.id == id }), videos[i].liked {
                videos[i].liked = false
                videos[i].likes = max(0, videos[i].likes - 1)
            }
        }
        schedulePersist()
    }

    func isVideoDownloaded(_ id: UUID) -> Bool { downloadedVideoIDs.contains(id) }

    func toggleVideoDownload(_ id: UUID) {
        if downloadedVideoIDs.contains(id) { downloadedVideoIDs.remove(id) }
        else { downloadedVideoIDs.insert(id) }
        schedulePersist()
    }

    func reportVideo(_ id: UUID) {
        if watchingVideoID == id { closeWatching() }
        videos.removeAll { $0.id == id }
        dislikedVideoIDs.remove(id)
        downloadedVideoIDs.remove(id)
        schedulePersist()
    }

    func videoShareURL(for id: UUID) -> URL {
        URL(string: "https://gojogo.app/w/\(id.uuidString.lowercased())")!
    }

    func shortShareURL(for id: UUID) -> URL {
        URL(string: "https://gojogo.app/s/\(id.uuidString.lowercased())")!
    }

    // MARK: Profile

    func toggleNotify(handle: String) {
        let key = handle.lowercased()
        if notifyHandles.contains(key) { notifyHandles.remove(key) }
        else { notifyHandles.insert(key) }
        schedulePersist()
    }

    func updateProfile(name: String, bio: String, category: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanName.isEmpty { user.name = cleanName }
        user.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        user.category = category
        if profileUser?.isOwn == true {
            profileUser = .own(from: user, posts: myPosts.count)
        }
        schedulePersist()
    }

    // MARK: Profile Home (customizable canvas)

    /// Generates a unique starter layout the first time the Home tab is opened.
    func seedProfileHomeIfNeeded() {
        guard profileHomeBlocks.isEmpty else { return }
        profileHomeBlocks = SampleData.randomProfileHome(handle: user.handle, posts: myPosts)
        schedulePersist()
    }

    /// Random Home layouts generated for *other* users' profiles, keyed by handle.
    /// Not persisted — regenerated per session, stable while browsing.
    @Published var otherProfileHomes: [String: [ProfileHomeBlock]] = [:]

    /// Generates (once) a Home layout for another user's profile.
    func ensureOtherProfileHome(handle: String, posts: [Post]) {
        let key = handle.lowercased()
        guard otherProfileHomes[key] == nil else { return }
        otherProfileHomes[key] = SampleData.randomProfileHome(handle: handle, posts: posts)
    }

    func otherProfileHome(_ handle: String) -> [ProfileHomeBlock] {
        otherProfileHomes[handle.lowercased()] ?? []
    }

    /// Discards the current Home and rolls a fresh random layout.
    func shuffleProfileHome() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            profileHomeBlocks = SampleData.randomProfileHome(handle: user.handle, posts: myPosts)
        }
        schedulePersist()
    }

    var editingHomeBlock: ProfileHomeBlock? {
        guard let id = editingHomeBlockID else { return nil }
        return profileHomeBlocks.first(where: { $0.id == id })
    }

    func toggleProfileHomeEditing() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            profileHomeEditing.toggle()
        }
    }

    /// Adds a new block of the given kind and immediately opens its editor.
    func addHomeBlock(_ kind: ProfileHomeBlockKind) {
        var block = ProfileHomeBlock(kind: kind)
        switch kind {
        case .heading:  block.title = "New heading"; block.style = .plain
        case .banner:   block.title = ""
        case .text:     block.text = ""
        case .featured: block.title = "Featured"
        case .media:    block.title = "Photos & video"; block.columns = 3
        case .gallery:  block.title = "Gallery"; block.columns = 3
        case .link:     block.title = "Visit"; block.url = "https://"; block.style = .accent
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            profileHomeBlocks.append(block)
        }
        showHomeBlockPicker = false
        // Let the picker sheet finish dismissing before presenting the editor,
        // so the two sheets don't collide.
        let id = block.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.editingHomeBlockID = id
        }
        schedulePersist()
    }

    func updateHomeBlock(_ block: ProfileHomeBlock) {
        guard let i = profileHomeBlocks.firstIndex(where: { $0.id == block.id }) else { return }
        profileHomeBlocks[i] = block
        schedulePersist()
    }

    func deleteHomeBlock(_ id: UUID) {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            profileHomeBlocks.removeAll { $0.id == id }
        }
        if editingHomeBlockID == id { editingHomeBlockID = nil }
        schedulePersist()
    }

    /// Moves a block up (-1) or down (+1) in the stack.
    func moveHomeBlock(_ id: UUID, by offset: Int) {
        guard let i = profileHomeBlocks.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard profileHomeBlocks.indices.contains(j) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            profileHomeBlocks.swapAt(i, j)
        }
        schedulePersist()
    }

    /// Posts referenced by a block, in stored order (skips any that were deleted).
    func homeBlockPosts(_ block: ProfileHomeBlock) -> [Post] {
        block.postIDs.compactMap { id in posts.first(where: { $0.id == id }) }
    }

    func signOut() {
        persistTask?.cancel()
        travelMatchTask?.cancel()
        partnerOfferTask?.cancel()
        partnerJobTask?.cancel()
        SessionStore.clear()

        partnerRoles = []
        partnerOnboardingRole = nil
        partnerDashboardRole = nil
        partnerOnline = false
        partnerJob = nil
        partnerJobPhase = .idle
        partnerEarningsByRole = [:]
        partnerJobsByRole = [:]
        partnerRatingByRole = [:]

        profileHomeBlocks = []
        otherProfileHomes = [:]
        profileHomeEditing = false
        editingHomeBlockID = nil
        showHomeBlockPicker = false

        showProfile = false
        profileUser = nil
        showActivity = false
        showEditProfile = false
        viewingPostID = nil
        commentingPostID = nil
        dmPeer = nil
        dmThreads = [:]

        email = ""
        user = GGUser()
        interests = SampleData.interests
        stories = SampleData.stories
        posts = SampleData.posts
        videos = SampleData.videos
        shorts = SampleData.shorts
        products = SampleData.products
        featuredProduct = SampleData.featuredProduct
        people = SampleData.people
        profilePhotos = SampleData.profileGridURLs
        savedPostIDs = []
        commentsByPost = [:]
        chatMessages = []
        notifications = SampleData.notifications
        subscribedChannels = []
        dislikedVideoIDs = []
        downloadedVideoIDs = []
        notifyHandles = []
        tvShows = SampleData.tvShows
        tvHero = SampleData.tvHero
        activeTab = .home
        watchSubFeed = .feed
        travelPhase = .home
        onboardingStep = 1
        bootstrapFreshSession()

        withAnimation(.easeInOut(duration: 0.45)) { phase = .welcome }
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

    func toggleFeedVideoMute() {
        feedVideosMuted.toggle()
        ShortVideoPlayerCache.setAllMuted(feedVideosMuted)
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

    func publishPost(text: String?, imageData: Data?, videoURL: String? = nil,
                     mediaItems: [PostMediaItem] = []) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (trimmed?.isEmpty == false) ? trimmed : nil
        let slides = mediaItems
        let first = slides.first
        let resolvedImage = imageData ?? first?.imageData
        let resolvedVideo = videoURL ?? first?.videoURL
        guard body != nil || resolvedImage != nil || resolvedVideo != nil || !slides.isEmpty else { return }

        let post = Post(
            author: user.handle,
            meta: "just now",
            avatarGradient: user.avatarGradient,
            avatarURL: user.avatarURL,
            imageData: resolvedImage,
            videoURL: resolvedVideo,
            mediaItems: slides,
            imageAspect: resolvedImage != nil || resolvedVideo != nil || !slides.isEmpty ? 1.25 : 1.0,
            text: body,
            likeCount: 0,
            isHalfWidth: false
        )
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            posts.insert(post, at: 0)
            user.postCount += 1
        }
        schedulePersist()
        simulateEngagement(on: post.id)
    }

    /// Prototype delight: a fresh post starts collecting likes/comments after a beat.
    private func simulateEngagement(on postID: UUID) {
        let fans = people.map(\.name) + ["marta.st", "kal.eb", "sena.films"]
        let firstFan = fans.randomElement() ?? "dani"
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 3.0...5.0)) { [weak self] in
            guard let self, let i = self.posts.firstIndex(where: { $0.id == postID }) else { return }
            self.posts[i].likeCount += Int.random(in: 3...9)
            self.pushActivity(ActivityItem(
                kind: .like, actor: firstFan,
                text: "and others liked your post.",
                timeAgo: "now",
                avatarURL: "https://picsum.photos/seed/p-\(firstFan)/120/120",
                previewURL: self.posts[i].imageURL))
            self.schedulePersist()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 7.0...11.0)) { [weak self] in
            guard let self, let i = self.posts.firstIndex(where: { $0.id == postID }) else { return }
            let commenter = fans.randomElement() ?? "lea"
            let text = ["This is great 🔥", "Okay this goes hard.",
                        "More of this please.", "Instant save."].randomElement()!
            var list = self.commentsByPost[postID] ?? []
            list.insert(Comment(author: commenter, text: text,
                                avatarURL: "https://picsum.photos/seed/p-\(commenter)/120/120",
                                timeAgo: "now"), at: 0)
            self.commentsByPost[postID] = list
            self.posts[i].commentCount = list.count
            self.pushActivity(ActivityItem(
                kind: .comment, actor: commenter,
                text: "commented: “\(text)”",
                timeAgo: "now",
                avatarURL: "https://picsum.photos/seed/p-\(commenter)/120/120",
                previewURL: self.posts[i].imageURL))
            self.schedulePersist()
        }
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
            closeComposer()
            persistSession()
            return
        }

        // Photo / mixed photo+video attachments → one carousel when 2+.
        let feedMedia = composeAttachments.filter { $0.kind == .photo }
        let audios = composeAttachments.filter { $0.kind == .audio }
        let shorts = composeAttachments.filter { $0.kind == .short }
        let longForms = composeAttachments.filter { $0.kind == .longForm }

        if feedMedia.count >= 2 {
            let slides = feedMedia.map {
                PostMediaItem(
                    imageData: $0.imageData,
                    videoURL: Self.persistedVideoURL(from: $0.videoURL)
                )
            }
            publishPost(text: caption, imageData: slides.first?.imageData,
                        videoURL: slides.first?.videoURL, mediaItems: slides)
        } else if let att = feedMedia.first {
            publishPost(text: caption, imageData: att.imageData,
                        videoURL: Self.persistedVideoURL(from: att.videoURL),
                        mediaItems: [PostMediaItem(imageData: att.imageData,
                                                   videoURL: Self.persistedVideoURL(from: att.videoURL))])
        }

        for att in audios {
            publishPost(text: caption ?? "🎙 Voice note · \(att.durationLabel ?? "0:00")",
                        imageData: att.imageData)
        }

        for att in shorts {
            withAnimation {
                self.shorts.insert(
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
        }

        for att in longForms {
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

    /// Play a specific episode: marks it watched, updates show progress, then plays.
    func playEpisode(showID: UUID, episodeID: UUID) {
        func advance(_ show: inout TVShow) {
            guard let e = show.episodes.firstIndex(where: { $0.id == episodeID }) else { return }
            show.episodes[e].watched = true
            let watched = show.episodes.filter(\.watched).count
            show.progress = min(1, Double(watched) / Double(max(show.episodes.count, 1)))
        }
        if tvHero.id == showID {
            advance(&tvHero)
            if selectedTVShow?.id == showID { selectedTVShow = tvHero }
            playTVShow(tvHero)
        } else if let i = tvShows.firstIndex(where: { $0.id == showID }) {
            advance(&tvShows[i])
            if selectedTVShow?.id == showID { selectedTVShow = tvShows[i] }
            playTVShow(tvShows[i])
        }
        schedulePersist()
    }

    func toggleFollowPerson(_ id: UUID) {
        guard let i = people.firstIndex(where: { $0.id == id }) else { return }
        people[i].following.toggle()
        user.followingCount += people[i].following ? 1 : -1
        schedulePersist()
    }

    // MARK: Partner — become a driver / delivery partner

    /// True once the user can work this side of the marketplace.
    func isPartner(_ role: PartnerRole) -> Bool { partnerRoles.contains(role) }

    /// Entry point from the GojoTravel / GojoDelivery header button.
    /// Opens the working dashboard if already onboarded, else starts the flow.
    func openPartner(_ role: PartnerRole) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if partnerRoles.contains(role) {
            openPartnerDashboard(role)
        } else {
            startPartnerOnboarding(role)
        }
    }

    // MARK: Partner — onboarding flow

    func startPartnerOnboarding(_ role: PartnerRole) {
        partnerApplication = PartnerApplication(role: role)
        partnerAgreedToTerms = false
        partnerStakeProcessing = false
        partnerStep = .rules
        withAnimation(.easeInOut(duration: 0.28)) { partnerOnboardingRole = role }
    }

    func cancelPartnerOnboarding() {
        partnerStakeProcessing = false
        withAnimation(.easeInOut(duration: 0.28)) { partnerOnboardingRole = nil }
    }

    /// "I agree" on the rules page → move to the stake payment.
    func agreePartnerRules() {
        guard partnerAgreedToTerms else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeInOut(duration: 0.3)) { partnerStep = .stake }
    }

    /// Pay the $30 good-conduct stake (mock — no real charge), then start KYC.
    func payPartnerStake() {
        guard !partnerStakeProcessing else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        partnerStakeProcessing = true
        partnerJobTask?.cancel()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            partnerStakeProcessing = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.easeInOut(duration: 0.32)) { partnerStep = .kyc }
        }
    }

    var partnerKYCComplete: Bool { partnerApplication.isComplete }

    /// Submit the completed KYC → become a partner.
    func submitPartnerKYC() {
        guard let role = partnerOnboardingRole, partnerApplication.isComplete else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        partnerRoles.insert(role)
        // A verified partner keeps the name from their ID on file.
        withAnimation(.easeInOut(duration: 0.35)) { partnerStep = .done }
        schedulePersist()
    }

    /// Dismiss the completion screen; optionally jump straight into the dashboard.
    func finishPartnerOnboarding(openDashboard: Bool) {
        let role = partnerOnboardingRole
        withAnimation(.easeInOut(duration: 0.28)) { partnerOnboardingRole = nil }
        if openDashboard, let role {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.openPartnerDashboard(role)
            }
        }
    }

    // MARK: Partner — per-role stats

    func partnerEarnings(_ role: PartnerRole) -> Double { partnerEarningsByRole[role.rawValue] ?? 0 }
    func partnerJobs(_ role: PartnerRole) -> Int { partnerJobsByRole[role.rawValue] ?? 0 }
    func partnerRating(_ role: PartnerRole) -> Double { partnerRatingByRole[role.rawValue] ?? 5.0 }

    // MARK: Partner — working dashboard

    func openPartnerDashboard(_ role: PartnerRole) {
        partnerJobPhase = .idle
        partnerJob = nil
        partnerJobProgress = 0
        withAnimation(.easeInOut(duration: 0.3)) { partnerDashboardRole = role }
    }

    func closePartnerDashboard() {
        goOffline()
        withAnimation(.easeInOut(duration: 0.28)) { partnerDashboardRole = nil }
    }

    func togglePartnerOnline() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if partnerOnline { goOffline() } else { goOnline() }
    }

    private func goOnline() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { partnerOnline = true }
        scheduleNextOffer(initial: true)
    }

    private func goOffline() {
        partnerOfferTask?.cancel()
        // Never cancel an in-progress navigation job — that froze the car on the map.
        if partnerJobPhase == .offer {
            partnerJobTask?.cancel()
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            partnerOnline = false
            if partnerJobPhase == .offer {
                partnerJobPhase = .idle
                partnerJob = nil
            }
        }
    }

    /// Queue up an incoming request after a short delay.
    private func scheduleNextOffer(initial: Bool = false) {
        guard let role = partnerDashboardRole, partnerOnline else { return }
        partnerOfferTask?.cancel()
        partnerOfferTask = Task { @MainActor in
            let delay: UInt64 = initial ? 2_200_000_000 : UInt64.random(in: 3_000_000_000...5_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, partnerOnline, partnerJobPhase == .idle else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                partnerJob = SampleData.samplePartnerJob(role: role)
                partnerJobPhase = .offer
            }
        }
    }

    func declinePartnerJob() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.25)) {
            partnerJob = nil
            partnerJobPhase = .idle
        }
        scheduleNextOffer()
    }

    func acceptPartnerJob() {
        guard partnerJob != nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        partnerJobProgress = 0
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { partnerJobPhase = .toPickup }
        runPartnerJob()
    }

    /// Drives the accepted job through pickup → dropoff → completion,
    /// animating the partner's position along both legs for the map guide.
    private func runPartnerJob() {
        partnerJobTask?.cancel()
        partnerJobTask = Task { @MainActor in
            // ~20 fps along each leg for smooth marker motion.
            let legSteps = 120
            let tickNs: UInt64 = 75_000_000 // 75ms → ~9s per leg

            // Leg 1 — heading to pickup / restaurant.
            for step in 1...legSteps {
                try? await Task.sleep(nanoseconds: tickNs)
                guard !Task.isCancelled, partnerJob != nil else { return }
                partnerJobProgress = Double(step) / Double(legSteps)
            }
            guard !Task.isCancelled, partnerJob != nil else { return }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            partnerJobProgress = 0
            partnerJobPhase = .toDropoff

            // Leg 2 — trip / delivery in progress to the customer.
            for step in 1...legSteps {
                try? await Task.sleep(nanoseconds: tickNs)
                guard !Task.isCancelled, partnerJob != nil else { return }
                partnerJobProgress = Double(step) / Double(legSteps)
            }
            guard !Task.isCancelled, let job = partnerJob else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            partnerEarningsByRole[job.role.rawValue, default: 0] += job.fare
            partnerJobsByRole[job.role.rawValue, default: 0] += 1
            // No withAnimation — avoids leaving the nav map stuck mid-transition.
            partnerJobPhase = .completed
        }
    }

    /// Dismiss the completed-job card and return to waiting for offers.
    func clearCompletedPartnerJob() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.3)) {
            partnerJob = nil
            partnerJobProgress = 0
            partnerJobPhase = .idle
        }
        schedulePersist()
        scheduleNextOffer()
    }

    /// Label describing what the partner is doing right now (dashboard subtitle).
    var partnerStatusLine: String {
        guard let role = partnerDashboardRole else { return "" }
        switch partnerJobPhase {
        case .idle:
            return partnerOnline ? "Online · waiting for \(role.jobNoun) requests" : "You're offline"
        case .offer:
            return "New \(role.jobNoun) request"
        case .toPickup:
            return role == .driver ? "Heading to pickup" : "Heading to the restaurant"
        case .toDropoff:
            return role == .driver ? "Trip in progress" : "Delivering to customer"
        case .completed:
            return "\(role.jobNoun.capitalized) complete"
        }
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
            let driver = SampleData.sampleDriver(near: travelPickup, eta: max(2, eta / 2))
            travelDriver = driver
            travelPhase = .enRoute

            let pickupCoord = CLLocationCoordinate2D(
                latitude: travelPickup.latitude, longitude: travelPickup.longitude)
            let startCoord = CLLocationCoordinate2D(
                latitude: driver.latitude, longitude: driver.longitude)

            // Drive toward the customer — paced by distance so it never teleports.
            await animateTravelDriver(from: startCoord, to: pickupCoord, pace: .approaching)
            guard !Task.isCancelled else { return }

            travelPhase = .inTrip

            if let drop = travelDropoff {
                let dropCoord = CLLocationCoordinate2D(
                    latitude: drop.latitude, longitude: drop.longitude)
                let from = CLLocationCoordinate2D(
                    latitude: travelDriver?.latitude ?? pickupCoord.latitude,
                    longitude: travelDriver?.longitude ?? pickupCoord.longitude)
                await animateTravelDriver(from: from, to: dropCoord, pace: .inTrip)
            }
            guard !Task.isCancelled else { return }
            completeTravelTrip()
        }
    }

    private enum TravelDriverPace {
        case approaching  // driver → pickup
        case inTrip       // pickup → dropoff

        /// Same pace for both legs. Lower secondsPerKm = faster car.
        var secondsPerKm: Double { 9 }
        var minSeconds: Double { 16 }
        var maxSeconds: Double { 42 }
    }

    /// Moves `travelDriver` along a road route at a calm demo pace.
    private func animateTravelDriver(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        pace: TravelDriverPace
    ) async {
        let route = await MapboxDirections.route(from: from, to: to) ?? [from, to]
        let km = routePathLengthKm(route)
        let seconds = min(pace.maxSeconds, max(pace.minSeconds, km * pace.secondsPerKm))
        let steps = max(48, Int((seconds * 20).rounded())) // ~20 fps
        let tickNs = UInt64((seconds / Double(steps)) * 1_000_000_000)
        let startEta = max(1, Int(seconds / 60.0 + 0.5))
        for step in 1...steps {
            try? await Task.sleep(nanoseconds: tickNs)
            guard !Task.isCancelled else { return }
            let point = PartnerRoute.point(on: route, at: Double(step) / Double(steps))
            guard var driver = travelDriver else { return }
            driver.latitude = point.latitude
            driver.longitude = point.longitude
            let left = max(1, Int((Double(steps - step) / Double(steps) * Double(startEta)).rounded()))
            driver.etaMinutes = left
            travelDriver = driver
        }
    }

    private func routePathLengthKm(_ route: [CLLocationCoordinate2D]) -> Double {
        guard route.count > 1 else { return 0.5 }
        var meters = 0.0
        for i in 1..<route.count {
            meters += CLLocation(latitude: route[i - 1].latitude, longitude: route[i - 1].longitude)
                .distance(from: CLLocation(latitude: route[i].latitude, longitude: route[i].longitude))
        }
        return max(0.3, meters / 1000.0)
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

    // MARK: GojoDelivery

    var selectedDeliveryRestaurant: DeliveryRestaurant? {
        guard let id = selectedDeliveryRestaurantID else { return nil }
        return deliveryRestaurants.first(where: { $0.id == id })
    }

    var deliveryOrderRestaurant: DeliveryRestaurant? {
        guard let id = deliveryOrderRestaurantID else { return nil }
        return deliveryRestaurants.first(where: { $0.id == id })
    }

    var filteredDeliveryRestaurants: [DeliveryRestaurant] {
        var list = deliveryRestaurants
        if deliveryCategory != "All" {
            list = list.filter { $0.categories.contains(deliveryCategory) }
        }
        let q = deliverySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.name.lowercased().contains(q)
                    || $0.cuisine.lowercased().contains(q)
                    || $0.menu.contains { $0.items.contains { $0.name.lowercased().contains(q) } }
            }
        }
        return list
    }

    func openDeliveryRestaurant(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.28)) { selectedDeliveryRestaurantID = id }
    }

    func closeDeliveryRestaurant() {
        withAnimation(.easeInOut(duration: 0.28)) { selectedDeliveryRestaurantID = nil }
    }

    // MARK: GojoDelivery — cart

    var deliveryCartCount: Int { deliveryCart.reduce(0) { $0 + $1.qty } }

    var deliveryCartSubtotal: Double {
        deliveryCart.reduce(0) { $0 + $1.item.price * Double($1.qty) }
    }

    var deliveryFeeAmount: Double {
        guard let rid = deliveryCartRestaurantID,
              let r = deliveryRestaurants.first(where: { $0.id == rid }) else { return 1.49 }
        return r.feeLabel == "Free" ? 0 : 1.49
    }

    var deliveryServiceFee: Double { deliveryCart.isEmpty ? 0 : 0.99 }

    var deliveryCartTotal: Double {
        deliveryCartSubtotal + deliveryFeeAmount + deliveryServiceFee
    }

    func deliveryQty(of item: DeliveryMenuItem) -> Int {
        deliveryCart.first(where: { $0.id == item.id })?.qty ?? 0
    }

    /// Adds an item; starting a cart at a different restaurant replaces the old cart.
    func addDeliveryItem(_ item: DeliveryMenuItem, from restaurant: DeliveryRestaurant) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            if deliveryCartRestaurantID != restaurant.id {
                deliveryCart = []
                deliveryCartRestaurantID = restaurant.id
            }
            if let i = deliveryCart.firstIndex(where: { $0.id == item.id }) {
                deliveryCart[i].qty += 1
            } else {
                deliveryCart.append(DeliveryCartLine(item: item, qty: 1))
            }
        }
    }

    func decrementDeliveryItem(_ item: DeliveryMenuItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            guard let i = deliveryCart.firstIndex(where: { $0.id == item.id }) else { return }
            if deliveryCart[i].qty > 1 {
                deliveryCart[i].qty -= 1
            } else {
                deliveryCart.remove(at: i)
            }
            if deliveryCart.isEmpty {
                deliveryCartRestaurantID = nil
                showDeliveryCheckout = false
            }
        }
    }

    func clearDeliveryCart() {
        withAnimation(.easeOut(duration: 0.2)) {
            deliveryCart = []
            deliveryCartRestaurantID = nil
            showDeliveryCheckout = false
        }
    }

    // MARK: GojoDelivery — order lifecycle

    func placeDeliveryOrder() {
        guard !deliveryCart.isEmpty, let rid = deliveryCartRestaurantID else { return }
        deliveryOrderRestaurantID = rid
        deliveryOrderTotalLabel = String(format: "$%.2f", deliveryCartTotal)
        deliveryOrderSummary = deliveryCart
            .map { "\($0.qty)× \($0.item.name)" }
            .joined(separator: ", ")
        showDeliveryCheckout = false
        selectedDeliveryRestaurantID = nil
        deliveryCart = []
        deliveryCartRestaurantID = nil
        deliveryCourier = nil
        deliveryCourierProgress = 0
        deliveryRating = 0
        deliveryEtaMinutes = (deliveryOrderRestaurant?.etaMinutes ?? 20)
        withAnimation(.easeInOut(duration: 0.3)) { deliveryStatus = .confirmed }

        deliveryTask?.cancel()
        deliveryTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { deliveryStatus = .preparing }

            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            deliveryCourier = SampleData.sampleCourier()
            deliveryEtaMinutes = max(8, deliveryEtaMinutes - 6)
            withAnimation(.easeInOut(duration: 0.3)) { deliveryStatus = .courierToRestaurant }

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { deliveryStatus = .delivering }

            // Courier rides from the restaurant to your door.
            let steps = 24
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: 420_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: 0.42)) {
                    deliveryCourierProgress = Double(step) / Double(steps)
                }
                if step % 6 == 0 {
                    deliveryEtaMinutes = max(1, deliveryEtaMinutes - 2)
                }
            }

            guard !Task.isCancelled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.easeInOut(duration: 0.35)) { deliveryStatus = .delivered }
        }
    }

    /// Cancels while the kitchen still has it — once the courier is moving it's locked.
    var canCancelDeliveryOrder: Bool {
        guard let s = deliveryStatus else { return false }
        return s < .delivering
    }

    func cancelDeliveryOrder() {
        deliveryTask?.cancel()
        deliveryCourier = nil
        deliveryCourierProgress = 0
        deliveryOrderRestaurantID = nil
        withAnimation(.easeInOut(duration: 0.3)) { deliveryStatus = nil }
    }

    func finishDeliveryOrder() {
        deliveryTask?.cancel()
        if let r = deliveryOrderRestaurant {
            deliveryPastOrders.insert(DeliveryPastOrder(
                restaurantName: r.name,
                imageURL: r.imageURL,
                itemsSummary: deliveryOrderSummary,
                totalLabel: deliveryOrderTotalLabel,
                dateLabel: "Today",
                rating: deliveryRating
            ), at: 0)
        }
        deliveryCourier = nil
        deliveryCourierProgress = 0
        deliveryOrderRestaurantID = nil
        deliveryRating = 0
        withAnimation(.easeInOut(duration: 0.3)) { deliveryStatus = nil }
    }

    // MARK: Madeleine chat

    func sendMadeleine(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chatMessages.append(ChatMessage(text: trimmed, fromUser: true))
        schedulePersist()

        let (reply, chip) = madeleineReply(to: trimmed)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.6...1.1)) { [weak self] in
            guard let self else { return }
            self.chatMessages.append(ChatMessage(text: reply, fromUser: false))
            if let chip {
                self.chatMessages.append(ChatMessage(text: "", fromUser: false, fileChip: chip))
            }
            self.schedulePersist()
        }
    }

    /// Lightweight on-device intent matching (prototype — no backend).
    private func madeleineReply(to text: String) -> (String, FileChip?) {
        let lower = text.lowercased()
        let name = user.name

        if lower.contains("feed") || lower.contains("summar") {
            let top = posts.max(by: { $0.likeCount < $1.likeCount })
            let reply = "Your feed has \(posts.count) posts right now. The one doing best is from \(top?.author ?? "marta.st") with \(formatCount(top?.likeCount ?? 0)) likes. You have \(unreadActivityCount) unread notifications — want the highlights?"
            return (reply, FileChip(name: "feed-digest.pdf", sub: "\(posts.count) posts · 1 min read"))
        }
        if lower.contains("weekend") || lower.contains("plan") {
            return ("Here's your weekend: Saturday 10:00 — 5-a-side at Mission Dolores Park (3 spots left). Saturday night — City Night Live is streaming on GojoTV. Sunday — night market walk, weather looks clear. Want me to pin all three?", nil)
        }
        if lower.contains("football") || lower.contains("group") {
            return ("Found 3 open football groups within 4 km: Sunday League (11-a-side, competitive), Dolores 5-a-side (casual, Sat mornings), and Night Kicks (weekdays, floodlit). Want me to request an invite to any of them?", nil)
        }
        if lower.contains("homework") || lower.contains("study") || lower.contains("essay") {
            return ("Happy to help, \(name). Drop the assignment here or tell me the topic — I'll build an outline, sources, and a study plan you can actually follow.",
                    FileChip(name: "study-plan.pdf", sub: "outline · 5 steps"))
        }
        if lower.contains("ride") || lower.contains("taxi") || lower.contains("airport") || lower.contains("go to") {
            return ("I can get you a ride. A GojoGo to SFO is about $38 and 4 minutes away right now. Open GojoTravel and I'll pre-fill the destination.", nil)
        }
        if lower.contains("sell") || lower.contains("listing") {
            return ("Selling is easy: snap a photo, set a price, and I'll suggest a category. Similar items near you are going for $30–$300 depending on condition. Tap Sell in Economy to start.", nil)
        }
        if lower.contains("buy") || lower.contains("phone") || lower.contains("camera") {
            let match = products.first(where: { lower.contains($0.category.lowercased()) }) ?? featuredProduct
            return ("Best match nearby: \(match.name) at \(match.price), \(match.distance) away from \(match.seller). Condition is listed as \(match.condition.lowercased()). Want me to open it?", nil)
        }
        if lower.contains("watch") || lower.contains("show") || lower.contains("movie") {
            let pick = tvShows.randomElement()?.title ?? "Night Signal"
            return ("Based on what you've been watching, try “\(pick)” tonight — it's trending on GojoTV. You're also \(Int((tvHero.progress) * 100))% through \(tvHero.title) if you'd rather finish that.", nil)
        }
        if lower.contains("hello") || lower.contains("hey") || lower.contains("hi ") || lower == "hi" {
            return ("Hey \(name)! I can plan your weekend, summarize your feed, find rides, or hunt deals on Economy. What do you need?", nil)
        }
        if lower.contains("thank") {
            return ("Anytime. That's what I'm here for.", nil)
        }
        let fallbacks = [
            "Got it — I'll keep an eye on that. Anything else while I'm at it?",
            "Noted. I'll surface anything relevant in your feed and ping you.",
            "On it. Give me a moment and check your notifications.",
            "Interesting — tell me a bit more and I can act on it.",
        ]
        return (fallbacks.randomElement()!, nil)
    }
}
