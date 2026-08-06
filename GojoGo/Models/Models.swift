import SwiftUI

// MARK: - Navigation enums

/// Top-level app section: private social (My World) vs public superapp (Collections).
enum AppNavMode: String, Hashable {
    case myWorld
    case collections
}

enum AppTab: Hashable { case home, watch, madeleine, travel, delivery, economy, search }

/// The three halves of the Economy tab. Marketplace is the C2C shelf that has
/// been there since 2b M1; Shops and Services are Phase 5's two catalogs, which
/// share a tab rather than taking two more because they are the same errand —
/// somebody selling something — seen from three angles.
enum EconomySegment: String, Hashable, CaseIterable, Identifiable {
    case marketplace
    case shops
    case services

    var id: String { rawValue }

    var label: String {
        switch self {
        case .marketplace: return "Marketplace"
        case .shops: return "Shops"
        case .services: return "Services"
        }
    }

    var icon: String {
        switch self {
        case .marketplace: return "tag.fill"
        case .shops: return "bag.fill"
        case .services: return "wrench.and.screwdriver.fill"
        }
    }
}

/// App-wide appearance. Media-immersive surfaces (stories, shorts, players)
/// stay dark in both themes by design.
enum AppTheme: String, Hashable {
    case dark
    case light

    var colorScheme: ColorScheme { self == .light ? .light : .dark }
}

/// Destinations inside My World (iMessage-style private network).
enum MyWorldTab: Hashable {
    case messages
    case circles
    case profile
}

// MARK: - GojoTravel

enum TravelPhase: Equatable {
    case home
    case searching
    case choosingRide
    case matching
    case enRoute
    case inTrip
    case completed
}

struct TravelPlace: Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
    var icon: String

    init(id: UUID = UUID(), name: String, subtitle: String,
         latitude: Double, longitude: Double, icon: String = "mappin") {
        self.id = id; self.name = name; self.subtitle = subtitle
        self.latitude = latitude; self.longitude = longitude; self.icon = icon
    }

    var coordinate: (lat: Double, lon: Double) { (latitude, longitude) }
}

/// How trustworthy the pickup point currently is.
///
/// `.unknown` is the placeholder the app opens with and is *not* a location —
/// a car sent to it would go to a city the rider has never been to, so the UI
/// has to say so rather than quietly showing a pin.
enum TravelPickupState: Equatable {
    case unknown
    case locating
    /// A real GPS fix. The associated name is what the reverse geocode called it.
    case live
    /// The rider turned location off for GojoGo.
    case denied
    /// Permission is fine, no fix arrived.
    case unavailable

    var isReal: Bool { self == .live }
}

struct RideOption: Identifiable, Equatable {
    let id: UUID
    var name: String
    var tagline: String
    var etaMinutes: Int
    var price: String
    var capacity: Int
    var icon: String

    init(id: UUID = UUID(), name: String, tagline: String,
         etaMinutes: Int, price: String, capacity: Int, icon: String) {
        self.id = id; self.name = name; self.tagline = tagline
        self.etaMinutes = etaMinutes; self.price = price
        self.capacity = capacity; self.icon = icon
    }
}

struct TravelDriver: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rating: Double
    var trips: Int
    var vehicle: String
    var plate: String
    var etaMinutes: Int
    var avatarURL: String?
    var latitude: Double
    var longitude: Double

    init(id: UUID = UUID(), name: String, rating: Double, trips: Int,
         vehicle: String, plate: String, etaMinutes: Int,
         avatarURL: String? = nil, latitude: Double, longitude: Double) {
        self.id = id; self.name = name; self.rating = rating; self.trips = trips
        self.vehicle = vehicle; self.plate = plate; self.etaMinutes = etaMinutes
        self.avatarURL = avatarURL; self.latitude = latitude; self.longitude = longitude
    }
}

enum WatchSubFeed: String, CaseIterable, Identifiable {
    case feed = "Feed", shorts = "Shorts", tv = "TV"
    var id: String { rawValue }
}

enum AuthPhase { case welcome, email, onboarding, app }

// MARK: - User

struct GGUser {
    var name: String = ""
    var handle: String = ""
    var birthYear: Int = 2004
    var interests: [String] = []
    var avatarGradient: [Color] = [Color(hex: "26303F"), Color(hex: "141821")]
    var avatarURL: String? = nil
    var followingCount: Int = 0
    var followerCount: Int = 0
    var postCount: Int = 0
    var bio: String = ""
    var category: String = "Creator"
}

/// Lightweight profile target for Instagram-style profile sheets.
struct ProfileUser: Identifiable {
    var id: String { handle.lowercased() }
    var name: String
    var handle: String
    var avatarURL: String?
    var avatarGradient: [Color]
    var bio: String
    var category: String
    var postCount: Int
    var followerCount: Int
    var followingCount: Int
    var isOwn: Bool
    var following: Bool
    /// A business profile (Phase 2e M1). A business *is* a profile, so this
    /// screen renders one — these three just change what it shows.
    var isBusiness: Bool = false
    /// KYC-approved. The only badge in the app that means anything.
    var verified: Bool = false
    /// The viewer owns this business — turns the page into theirs to edit.
    var isBusinessOwner: Bool = false
    var business: BusinessContact? = nil

    static func own(from user: GGUser, posts: Int) -> ProfileUser {
        ProfileUser(
            name: user.name,
            handle: user.handle,
            avatarURL: user.avatarURL,
            avatarGradient: user.avatarGradient,
            bio: user.bio,
            category: user.category,
            postCount: posts,
            followerCount: user.followerCount,
            followingCount: user.followingCount,
            isOwn: true,
            following: false
        )
    }
}

/// The business-only block on a profile: how to reach it and where it is.
struct BusinessContact: Equatable {
    var phone: String
    var email: String
    var website: String
    var addressLine: String
    var city: String
    var country: String
    var openingHours: String

    var addressSummary: String {
        [addressLine, city, country]
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: ", ")
    }

    var isEmpty: Bool {
        addressSummary.isEmpty && phone.isEmpty && email.isEmpty
            && website.isEmpty && openingHours.isEmpty
    }
}

// MARK: - Content models

/// One frame of a story — a photo, a video, or a text card.
///
/// `imageData` / `localVideoURL` are the on-device copies that exist between
/// posting and the upload landing; once the server answers, the URL fields take
/// over. Counts and `myReaction` come from the server and are nil on frames
/// that aren't yours (viewer analytics) or haven't synced yet.
struct StoryFrame: Identifiable, Equatable {
    let id: UUID
    var kind: StoryMediaKind
    var imageURL: String?
    var imageData: Data?
    var videoURL: String?
    var localVideoURL: URL?
    var durationMs: Int?
    var caption: String?
    var background: StoryBackground
    var overlays: [StoryOverlay]
    var audience: StoryAudience
    var music: StoryMusic?
    var seen: Bool
    var viewerCount: Int?
    var replyCount: Int?
    var myReaction: String?
    var createdAt: Date?
    var expiresAt: Date?

    init(id: UUID = UUID(), kind: StoryMediaKind = .image,
         imageURL: String? = nil, imageData: Data? = nil,
         videoURL: String? = nil, localVideoURL: URL? = nil,
         durationMs: Int? = nil, caption: String? = nil,
         background: StoryBackground = .ink, overlays: [StoryOverlay] = [],
         audience: StoryAudience = .everyone, music: StoryMusic? = nil,
         seen: Bool = false,
         viewerCount: Int? = nil, replyCount: Int? = nil, myReaction: String? = nil,
         createdAt: Date? = nil, expiresAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.imageURL = imageURL
        self.imageData = imageData
        self.videoURL = videoURL
        self.localVideoURL = localVideoURL
        self.durationMs = durationMs
        self.caption = caption
        self.background = background
        self.overlays = overlays
        self.audience = audience
        self.music = music
        self.seen = seen
        self.viewerCount = viewerCount
        self.replyCount = replyCount
        self.myReaction = myReaction
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    /// A text card is "renderable" with no media at all; the others need theirs.
    var hasContent: Bool {
        switch kind {
        case .text: caption?.isEmpty == false
        case .video: videoURL != nil || localVideoURL != nil
        case .image: imageURL != nil || imageData != nil
        }
    }

    /// Playable video source — the local file wins while an upload is in flight.
    var playableVideo: String? {
        if let localVideoURL { return localVideoURL.absoluteString }
        return videoURL
    }

    /// How long this frame holds the screen. Instagram gives a still 5 seconds
    /// and a video its own length, capped so one long clip can't stall the rail
    /// — and a still carrying a sound plays for as long as the sound does, so
    /// the clip isn't cut off mid-bar.
    var displayDuration: Double {
        if kind == .video, let durationMs, durationMs > 0 {
            return min(Double(durationMs) / 1000, 60)
        }
        if let music {
            return min(max(music.clipSeconds, 1), 15)
        }
        return 5
    }
}

/// One person’s story ring — may contain multiple frames.
struct Story: Identifiable {
    let id: UUID
    let name: String
    let letter: String
    let gradient: [Color]
    var frames: [StoryFrame]
    var isYou: Bool
    /// The author's profile picture — what the ring and the viewer header show.
    var avatarURL: String?
    /// Muted rings sort last and render dimmed; they stay openable.
    var muted: Bool

    var seen: Bool {
        frames.isEmpty || frames.allSatisfy(\.seen)
    }

    /// Cover art for the rail cell — the first frame that actually has a picture.
    var imageURL: String? {
        frames.first(where: { $0.imageURL != nil })?.imageURL
    }
    var imageData: Data? {
        frames.first(where: { $0.imageData != nil })?.imageData
    }
    var hasMedia: Bool { frames.contains(where: \.hasContent) }
    var hasCloseFriendsFrame: Bool { frames.contains { $0.audience == .closeFriends } }

    init(id: UUID = UUID(), name: String, letter: String, gradient: [Color],
         frames: [StoryFrame] = [], isYou: Bool = false,
         avatarURL: String? = nil, muted: Bool = false) {
        self.id = id; self.name = name; self.letter = letter
        self.gradient = gradient; self.frames = frames; self.isYou = isYou
        self.avatarURL = avatarURL; self.muted = muted
    }
}

struct Post: Identifiable {
    let id: UUID
    let author: String
    var meta: String
    let avatarGradient: [Color]
    var avatarURL: String?
    var imageURL: String?
    var imageData: Data?
    /// Local file or remote HTTP URL for in-feed playback.
    var videoURL: String?
    /// A voice post: a durable local ref (`gojoaudio:…`) until the upload lands,
    /// the uploaded m4a afterwards. Voice posts carry no picture — they render
    /// as a waveform wherever a written post renders as text.
    var audioURL: String?
    /// Extra slides for a multi-photo / video carousel post (includes the first slide).
    var mediaItems: [PostMediaItem]
    var imageAspect: CGFloat   // height / width hint for layout
    var text: String?
    /// People tagged in the caption, resolved server-side at publish time.
    var mentions: [Mention]
    var showFollow: Bool
    var liked: Bool
    var bookmarked: Bool
    var following: Bool
    var likeCount: Int
    var commentCount: Int
    var isHalfWidth: Bool

    var isVideo: Bool {
        if let videoURL, !videoURL.isEmpty { return true }
        return mediaItems.contains(where: \.isVideo)
    }

    var isCarousel: Bool { mediaItems.count > 1 }

    var isAudio: Bool { !(audioURL ?? "").isEmpty }

    /// What the player is handed — the durable local recording while the upload
    /// is still in flight, the remote m4a once it has landed.
    var playableAudioURL: URL? { AudioLibrary.playableURL(audioURL) }

    /// Slides to render — prefers explicit carousel items, else legacy single media.
    var carouselSlides: [PostMediaItem] {
        if !mediaItems.isEmpty { return mediaItems }
        if imageURL != nil || imageData != nil || (videoURL != nil && !(videoURL?.isEmpty ?? true)) {
            return [PostMediaItem(imageURL: imageURL, imageData: imageData, videoURL: videoURL)]
        }
        return []
    }

    init(id: UUID = UUID(), author: String, meta: String,
         avatarGradient: [Color], avatarURL: String? = nil,
         imageURL: String? = nil, imageData: Data? = nil,
         videoURL: String? = nil,
         audioURL: String? = nil,
         mediaItems: [PostMediaItem] = [],
         imageAspect: CGFloat = 1.0, text: String? = nil,
         mentions: [Mention] = [],
         showFollow: Bool = false, liked: Bool = false,
         bookmarked: Bool = false, following: Bool = false,
         likeCount: Int = 0, commentCount: Int = 0,
         isHalfWidth: Bool = false) {
        self.id = id; self.author = author; self.meta = meta
        self.avatarGradient = avatarGradient; self.avatarURL = avatarURL
        self.imageURL = imageURL; self.imageData = imageData
        self.videoURL = videoURL
        self.audioURL = audioURL
        self.mediaItems = mediaItems
        self.imageAspect = imageAspect; self.text = text
        self.mentions = mentions
        self.showFollow = showFollow; self.liked = liked
        self.bookmarked = bookmarked; self.following = following
        self.likeCount = likeCount; self.commentCount = commentCount
        self.isHalfWidth = isHalfWidth
    }
}

struct PostMediaItem: Identifiable, Equatable {
    let id: UUID
    var imageURL: String?
    var imageData: Data?
    var videoURL: String?

    var isVideo: Bool {
        if let videoURL, !videoURL.isEmpty { return true }
        return false
    }

    init(id: UUID = UUID(), imageURL: String? = nil, imageData: Data? = nil, videoURL: String? = nil) {
        self.id = id; self.imageURL = imageURL; self.imageData = imageData; self.videoURL = videoURL
    }
}

/// Local upload lifecycle for a Watch clip. Remote / sample items stay
/// `.published`; the publisher's optimistic row moves uploading → published
/// (or failed) so "instant publish" isn't mistaken for being live for others.
enum VideoPublishState: Equatable {
    case published
    case uploading(progress: Double)
    case failed(message: String)

    var isPending: Bool {
        switch self {
        case .published: return false
        case .uploading, .failed: return true
        }
    }

    var statusLabel: String? {
        switch self {
        case .published:
            return nil
        case .uploading(let progress):
            let pct = Int((max(0, min(1, progress)) * 100).rounded())
            return pct > 0 ? "Uploading \(pct)%…" : "Uploading…"
        case .failed:
            return "Upload failed · Tap to retry"
        }
    }
}

/// A long-form (Watch) video. Authored fields come from publish; counts come
/// from the live `watch` module when the id is server-backed.
struct VideoItem: Identifiable {
    let id: UUID
    var title: String
    let channel: String
    /// Author-written description shown on the watch page. Empty until written.
    var details: String
    let duration: String
    let thumbGradient: [Color]
    var thumbURL: String?
    var thumbData: Data?
    var videoURL: String?
    /// The author's avatar — never the video's own poster frame.
    var authorAvatarURL: String?
    var authorAvatarData: Data?
    var likes: Int
    var liked: Bool
    var saved: Bool
    /// Distinct viewers, counted server-side (one row per viewer, so a replay
    /// can't inflate it). Zero until someone opens it.
    var views: Int
    var commentCount: Int
    let publishedAt: Date
    var publishState: VideoPublishState

    init(id: UUID = UUID(), title: String, channel: String, details: String = "",
         duration: String, thumbGradient: [Color], thumbURL: String? = nil,
         thumbData: Data? = nil, videoURL: String? = nil,
         authorAvatarURL: String? = nil, authorAvatarData: Data? = nil,
         likes: Int = 0, liked: Bool = false, saved: Bool = false,
         views: Int = 0, commentCount: Int = 0, publishedAt: Date = Date(),
         publishState: VideoPublishState = .published) {
        self.id = id; self.title = title; self.channel = channel; self.details = details
        self.duration = duration; self.thumbGradient = thumbGradient
        self.thumbURL = thumbURL; self.thumbData = thumbData; self.videoURL = videoURL
        self.authorAvatarURL = authorAvatarURL; self.authorAvatarData = authorAvatarData
        self.likes = likes; self.liked = liked; self.saved = saved
        self.views = views; self.commentCount = commentCount; self.publishedAt = publishedAt
        self.publishState = publishState
    }

    /// "1.2K views · 3h" — or upload status while the publisher's copy is still syncing.
    var meta: String {
        if let status = publishState.statusLabel { return status }
        let viewPart = views == 1 ? "1 view" : "\(formatCount(views)) views"
        return "\(viewPart) · \(RelativeTime.since(publishedAt))"
    }
}

struct Short: Identifiable {
    let id: UUID
    let channel: String
    var caption: String
    let gradient: [Color]
    var imageURL: String?
    var imageData: Data?
    /// Local file or remote HTTP URL for playback.
    var videoURL: String?
    /// The author's avatar — never the clip's own poster frame.
    var authorAvatarURL: String?
    var authorAvatarData: Data?
    var liked: Bool
    var bookmarked: Bool
    var following: Bool
    var likeCount: Int
    var views: Int
    let publishedAt: Date
    var publishState: VideoPublishState

    init(id: UUID = UUID(), channel: String, caption: String,
         gradient: [Color], imageURL: String? = nil, imageData: Data? = nil,
         videoURL: String? = nil,
         authorAvatarURL: String? = nil, authorAvatarData: Data? = nil,
         liked: Bool = false, bookmarked: Bool = false, following: Bool = false,
         likeCount: Int = 0, views: Int = 0, publishedAt: Date = Date(),
         publishState: VideoPublishState = .published) {
        self.id = id; self.channel = channel
        self.caption = caption; self.gradient = gradient; self.imageURL = imageURL
        self.imageData = imageData; self.videoURL = videoURL
        self.authorAvatarURL = authorAvatarURL; self.authorAvatarData = authorAvatarData
        self.liked = liked; self.bookmarked = bookmarked; self.following = following
        self.likeCount = likeCount
        self.views = views; self.publishedAt = publishedAt
        self.publishState = publishState
    }
}

/// Age of a locally-authored item. The backend equivalent is `BackendDate.relative`.
enum RelativeTime {
    static func since(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60))m ago"
        case ..<86_400: return "\(Int(seconds / 3600))h ago"
        case ..<604_800: return "\(Int(seconds / 86_400))d ago"
        default: return "\(Int(seconds / 604_800))w ago"
        }
    }
}

struct Product: Identifiable {
    let id: UUID
    let name: String
    let price: String
    var meta: String
    let gradient: [Color]
    var imageURL: String?
    var saved: Bool
    var category: String
    var seller: String
    var condition: String
    var distance: String
    var description: String
    /// Live / paused / sold. A saved listing can go sold under the buyer, so the
    /// detail view says so instead of offering to message about a gone item.
    var status: ListingStatus

    init(id: UUID = UUID(), name: String, price: String, meta: String = "",
         gradient: [Color], imageURL: String? = nil, saved: Bool = false,
         category: String = "All", seller: String = "seller",
         condition: String = "Good", distance: String = "nearby",
         description: String = "", status: ListingStatus = .active) {
        self.id = id; self.name = name; self.price = price; self.meta = meta
        self.gradient = gradient; self.imageURL = imageURL; self.saved = saved
        self.category = category; self.seller = seller
        self.condition = condition; self.distance = distance
        self.status = status
        self.description = description.isEmpty
            ? "Listed on GojoGo Economy. Message the seller to ask about pickup, bundle deals, or more photos."
            : description
    }
}

struct PersonSuggestion: Identifiable {
    let id: UUID
    let name: String
    let gradient: [Color]
    var avatarURL: String?
    var following: Bool

    init(id: UUID = UUID(), name: String, gradient: [Color],
         avatarURL: String? = nil, following: Bool = false) {
        self.id = id; self.name = name; self.gradient = gradient
        self.avatarURL = avatarURL; self.following = following
    }
}

struct TVShow: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let synopsis: String
    let badge: String
    let gradient: [Color]
    var imageURL: String?
    var videoIDHint: String?
    var progress: Double
    var episodes: [TVEpisode]
    var onWatchlist: Bool

    init(id: UUID = UUID(), title: String, subtitle: String, synopsis: String,
         badge: String = "SERIES", gradient: [Color], imageURL: String? = nil,
         videoIDHint: String? = nil, progress: Double = 0,
         episodes: [TVEpisode] = [], onWatchlist: Bool = false) {
        self.id = id; self.title = title; self.subtitle = subtitle
        self.synopsis = synopsis; self.badge = badge; self.gradient = gradient
        self.imageURL = imageURL; self.videoIDHint = videoIDHint
        self.progress = progress; self.episodes = episodes
        self.onWatchlist = onWatchlist
    }
}

struct TVEpisode: Identifiable {
    let id: UUID
    let number: Int
    let title: String
    let duration: String
    var watched: Bool

    init(id: UUID = UUID(), number: Int, title: String, duration: String, watched: Bool = false) {
        self.id = id; self.number = number; self.title = title
        self.duration = duration; self.watched = watched
    }
}

struct TVPoster: Identifiable {
    let id: UUID
    let rank: Int
    let title: String
    let gradient: [Color]
    var imageURL: String?
    var showID: UUID?

    init(id: UUID = UUID(), rank: Int, title: String = "",
         gradient: [Color], imageURL: String? = nil, showID: UUID? = nil) {
        self.id = id; self.rank = rank; self.title = title
        self.gradient = gradient; self.imageURL = imageURL; self.showID = showID
    }
}

struct TVTile: Identifiable {
    let id: UUID
    let title: String
    let gradient: [Color]
    var imageURL: String?
    var showID: UUID?

    init(id: UUID = UUID(), title: String, gradient: [Color],
         imageURL: String? = nil, showID: UUID? = nil) {
        self.id = id; self.title = title; self.gradient = gradient
        self.imageURL = imageURL; self.showID = showID
    }
}

struct Interest: Identifiable {
    let id: UUID
    let title: String
    var selected: Bool
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    var accent: [Color]?

    init(id: UUID = UUID(), title: String, selected: Bool = false,
         x: CGFloat, y: CGFloat, size: CGFloat, accent: [Color]? = nil) {
        self.id = id; self.title = title; self.selected = selected
        self.x = x; self.y = y; self.size = size; self.accent = accent
    }
}

struct ChatMessage: Identifiable {
    let id: UUID
    let text: String
    let fromUser: Bool
    var fileChip: FileChip?

    init(id: UUID = UUID(), text: String, fromUser: Bool, fileChip: FileChip? = nil) {
        self.id = id; self.text = text; self.fromUser = fromUser; self.fileChip = fileChip
    }
}

struct FileChip: Identifiable {
    let id: UUID
    let name: String
    let sub: String
    var tint: Color

    init(id: UUID = UUID(), name: String, sub: String, tint: Color = GGColor.accent) {
        self.id = id; self.name = name; self.sub = sub; self.tint = tint
    }
}

// MARK: - Activity / notifications

/// Raw values are the server's notification `type` — a new one there needs a
/// case here or it renders as `.system`.
enum ActivityKind: String {
    case like, comment, reply, follow, mention, order, system

    var icon: String {
        switch self {
        case .like: return "heart.fill"
        case .comment: return "bubble.right.fill"
        case .reply: return "arrowshape.turn.up.left.fill"
        case .follow: return "person.fill.badge.plus"
        case .mention: return "at"
        case .order: return "bag.fill"
        case .system: return "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .like: return Color(hex: "E85D75")
        case .comment, .reply: return GGColor.blue
        case .follow: return Color(hex: "7A6CF0")
        case .mention: return Color(hex: "E8B45D")
        case .order: return Color(hex: "5DC98A")
        case .system: return GGColor.accent
        }
    }
}

struct ActivityItem: Identifiable {
    let id: UUID
    var kind: ActivityKind
    var actor: String
    var text: String
    var timeAgo: String
    var read: Bool
    var avatarURL: String?
    var previewURL: String?
    /// What this is about, when it is about something — a tap opens it instead
    /// of guessing at the user's most recent post.
    var postID: UUID?

    init(id: UUID = UUID(), kind: ActivityKind, actor: String, text: String,
         timeAgo: String, read: Bool = false, avatarURL: String? = nil,
         previewURL: String? = nil, postID: UUID? = nil) {
        self.id = id; self.kind = kind; self.actor = actor; self.text = text
        self.timeAgo = timeAgo; self.read = read; self.avatarURL = avatarURL
        self.previewURL = previewURL; self.postID = postID
    }
}

/// Someone tagged in a caption or a comment. `handle` is the handle as it was
/// written, which is the token to underline in the body; `profileID` is where a
/// tap goes, and it stays right when that person renames.
struct Mention: Identifiable, Hashable, Codable {
    let profileID: UUID
    let handle: String

    var id: UUID { profileID }

    init(profileID: UUID, handle: String) {
        self.profileID = profileID
        self.handle = handle
    }
}

/// A row in the @-tag autocomplete. Its own type rather than a reuse of
/// `PersonSuggestion`, which is the follow-suggestion rail's shape and carries a
/// `following` flag the picker has no business showing.
struct MentionCandidate: Identifiable, Hashable {
    let id: UUID
    let name: String
    let handle: String
    var avatarURL: String?
    var verified: Bool = false
    var business: Bool = false
}

/// One level of nesting, deliberately: `replies` is populated on a top-level
/// comment and always empty on a reply. Who a reply is answering is carried by
/// the `@handle` in its own text, not by a deeper tree.
struct Comment: Identifiable, Hashable {
    let id: UUID
    let author: String
    let text: String
    var avatarURL: String?
    var liked: Bool
    var likeCount: Int
    let timeAgo: String
    /// The comment this answers; nil on a top-level comment.
    var parentID: UUID?
    /// The server's true total, which may exceed `replies.count` before the
    /// thread is expanded.
    var replyCount: Int
    var mentions: [Mention]
    var replies: [Comment]

    init(id: UUID = UUID(), author: String, text: String,
         avatarURL: String? = nil, liked: Bool = false,
         likeCount: Int = 0, timeAgo: String = "just now",
         parentID: UUID? = nil, replyCount: Int = 0,
         mentions: [Mention] = [], replies: [Comment] = []) {
        self.id = id; self.author = author; self.text = text
        self.avatarURL = avatarURL; self.liked = liked
        self.likeCount = likeCount; self.timeAgo = timeAgo
        self.parentID = parentID; self.replyCount = replyCount
        self.mentions = mentions; self.replies = replies
    }
}

// MARK: - Compose (iMessage-style)

enum ComposeMediaKind: String {
    case textOnly, audio, short, longForm, photo
}

struct ComposeAttachment: Identifiable, Equatable {
    let id: UUID
    var kind: ComposeMediaKind
    /// Display / poster image (edited).
    var imageData: Data
    /// Unedited source image for Reset in the editor.
    var originalImageData: Data?
    var durationLabel: String?
    var audioURL: URL?
    var videoURL: URL?
    /// Normalized trim range for videos (0…1).
    var trimStart: Double
    var trimEnd: Double
    /// Long-form only — authored in the details sheet before publishing.
    var title: String
    var details: String

    var isVideo: Bool {
        videoURL != nil || kind == .short || kind == .longForm
    }

    init(id: UUID = UUID(), kind: ComposeMediaKind, imageData: Data,
         originalImageData: Data? = nil,
         durationLabel: String? = nil, audioURL: URL? = nil,
         videoURL: URL? = nil,
         trimStart: Double = 0, trimEnd: Double = 1,
         title: String = "", details: String = "") {
        self.id = id; self.kind = kind; self.imageData = imageData
        self.originalImageData = originalImageData ?? imageData
        self.durationLabel = durationLabel; self.audioURL = audioURL
        self.videoURL = videoURL
        self.trimStart = trimStart; self.trimEnd = trimEnd
        self.title = title; self.details = details
    }
}

// MARK: - My World (private social · iMessage-inspired)

// String-backed so the local message archive can persist it; raw values match
// the wire kinds (see AppState.wireKind).
enum WorldMessageKind: String, Codable {
    case text
    case emoji
    case file
    case photo
    case video
    case carousel
    case audio
    case location
    case poll
    case system
    case timestamp
    /// An image sticker (from the system sticker keyboard) — renders bare, no bubble.
    case sticker
}

/// The six iMessage tapbacks (+ their SF Symbol overlay glyph).
enum WorldTapback: String, CaseIterable, Identifiable {
    case heart, thumbsUp, thumbsDown, haha, exclaim, question
    var id: String { rawValue }

    /// Big glyph shown in the floating reaction picker.
    var pickerSymbol: String {
        switch self {
        case .heart:      return "heart.fill"
        case .thumbsUp:   return "hand.thumbsup.fill"
        case .thumbsDown: return "hand.thumbsdown.fill"
        case .haha:       return "face.smiling.fill"
        case .exclaim:    return "exclamationmark.2"
        case .question:   return "questionmark"
        }
    }

    /// Compact glyph baked into the badge that sticks to the bubble corner.
    var badgeSymbol: String {
        switch self {
        case .heart:      return "heart.fill"
        case .thumbsUp:   return "hand.thumbsup.fill"
        case .thumbsDown: return "hand.thumbsdown.fill"
        case .haha:       return "face.smiling.fill"
        case .exclaim:    return "exclamationmark.2"
        case .question:   return "questionmark"
        }
    }
}

/// A tapback reaction stuck to a bubble.
struct WorldReaction: Identifiable, Equatable {
    let id: UUID
    var tapback: WorldTapback
    var fromUser: Bool

    init(id: UUID = UUID(), tapback: WorldTapback, fromUser: Bool) {
        self.id = id; self.tapback = tapback; self.fromUser = fromUser
    }
}

/// A quoted snippet shown above a bubble when it's an inline reply.
struct WorldReplySnippet: Equatable {
    var authorName: String
    var preview: String
    var fromUser: Bool
}

/// A single poll option with its voters.
struct WorldPollOption: Identifiable, Equatable {
    let id: UUID
    var text: String
    /// Display names of everyone who picked this option ("You" for the user).
    var voters: [String]

    init(id: UUID = UUID(), text: String, voters: [String] = []) {
        self.id = id; self.text = text; self.voters = voters
    }
}

/// An iMessage-style poll embedded in a message.
struct WorldPoll: Equatable {
    var question: String
    var options: [WorldPollOption]
    /// Whether the user may pick more than one option.
    var allowsMultiple: Bool

    init(question: String, options: [WorldPollOption], allowsMultiple: Bool = true) {
        self.question = question; self.options = options; self.allowsMultiple = allowsMultiple
    }

    var totalVotes: Int { options.reduce(0) { $0 + $1.voters.count } }
    func youVoted(_ optionID: UUID) -> Bool {
        options.first { $0.id == optionID }?.voters.contains("You") ?? false
    }
}

/// One slide inside a chat media carousel (photo and/or video).
struct WorldCarouselItem: Identifiable, Equatable {
    let id: UUID
    var imageData: Data
    var isVideo: Bool
    var durationLabel: String?
    /// Remote URL for live (backend) messages; local `imageData` wins when set.
    var imageURL: String?
    /// The movie file behind a video slide (remote, then on-device).
    var videoURL: String?
    var localVideoURL: URL?

    init(id: UUID = UUID(), imageData: Data, isVideo: Bool = false,
         durationLabel: String? = nil, imageURL: String? = nil,
         videoURL: String? = nil, localVideoURL: URL? = nil) {
        self.id = id; self.imageData = imageData
        self.isVideo = isVideo; self.durationLabel = durationLabel
        self.imageURL = imageURL
        self.videoURL = videoURL; self.localVideoURL = localVideoURL
    }
}

/// Media staged in the chat composer before sending (iMessage-style preview tray).
struct WorldPendingAttachment: Identifiable {
    let id: UUID
    var imageData: Data
    var isVideo: Bool
    var durationLabel: String?
    /// The picked movie itself, kept on disk so it can be uploaded and played
    /// back — `imageData` is only its poster frame.
    var videoURL: URL?

    init(id: UUID = UUID(), imageData: Data, isVideo: Bool = false,
         durationLabel: String? = nil, videoURL: URL? = nil) {
        self.id = id; self.imageData = imageData
        self.isVideo = isVideo; self.durationLabel = durationLabel
        self.videoURL = videoURL
    }
}

struct WorldMessage: Identifiable {
    let id: UUID
    var kind: WorldMessageKind
    var text: String
    var fromUser: Bool
    var fileName: String?
    var fileMeta: String?
    var readLabel: String?
    /// When the other side read this message (used for "Read 3:42 PM" etc.).
    var readAt: Date?
    /// When the message was sent, as the server recorded it. The read receipt
    /// dates itself by this whenever the read instant itself isn't known — see
    /// `WorldChatView.receiptText`.
    var sentAt: Date?
    var imageData: Data?
    /// Remote URL for live (backend) photo/video messages; `imageData` wins when set.
    var imageURL: String?
    var durationLabel: String?
    var senderName: String?
    var carouselItems: [WorldCarouselItem]
    /// Tapbacks stuck to this bubble.
    var reactions: [WorldReaction]
    /// Quoted snippet when this is an inline reply.
    var replyTo: WorldReplySnippet?
    /// Poll payload for `.poll` messages.
    var poll: WorldPoll?
    /// Set while a Send-Later message is waiting to be delivered.
    var scheduledLabel: String?
    /// Remote audio file for `.audio` messages (uploaded m4a).
    var audioURL: String?
    /// On-device recording, playable before/while the upload finishes.
    var localAudioURL: URL?
    /// Movie behind a `.video` message — `imageData`/`imageURL` is its poster.
    var videoURL: String?
    var localVideoURL: URL?
    /// Coordinates for `.location` messages — real fix, openable in Maps.
    var latitude: Double?
    var longitude: Double?
    /// Set when this copy came off the wire as a sealed body this device could
    /// not open (E2EE Phase C). Transient and never archived: it describes one
    /// mapping of one server row, not the message. What it exists for is the
    /// merge — a ciphertext is spent after one read, so a refetched copy of
    /// something already in the archive arrives unreadable, and the archive's
    /// text must win rather than be replaced by an error.
    var isUndecryptable: Bool = false

    init(id: UUID = UUID(), kind: WorldMessageKind = .text, text: String,
         fromUser: Bool = false, fileName: String? = nil, fileMeta: String? = nil,
         readLabel: String? = nil, readAt: Date? = nil, sentAt: Date? = nil,
         imageData: Data? = nil, imageURL: String? = nil,
         durationLabel: String? = nil,
         senderName: String? = nil, carouselItems: [WorldCarouselItem] = [],
         reactions: [WorldReaction] = [], replyTo: WorldReplySnippet? = nil,
         poll: WorldPoll? = nil, scheduledLabel: String? = nil,
         audioURL: String? = nil, localAudioURL: URL? = nil,
         videoURL: String? = nil, localVideoURL: URL? = nil,
         latitude: Double? = nil, longitude: Double? = nil,
         isUndecryptable: Bool = false) {
        self.id = id; self.kind = kind; self.text = text; self.fromUser = fromUser
        self.fileName = fileName; self.fileMeta = fileMeta
        self.readLabel = readLabel; self.readAt = readAt; self.sentAt = sentAt
        self.imageData = imageData; self.imageURL = imageURL; self.durationLabel = durationLabel
        self.senderName = senderName; self.carouselItems = carouselItems
        self.reactions = reactions; self.replyTo = replyTo
        self.poll = poll; self.scheduledLabel = scheduledLabel
        self.audioURL = audioURL; self.localAudioURL = localAudioURL
        self.videoURL = videoURL; self.localVideoURL = localVideoURL
        self.latitude = latitude; self.longitude = longitude
        self.isUndecryptable = isUndecryptable
    }

    /// Playable source for an `.audio` bubble — the local recording wins so the
    /// sender hears it instantly, the CDN copy is what the recipient gets.
    var playableAudioURL: URL? {
        if let localAudioURL, FileManager.default.fileExists(atPath: localAudioURL.path) {
            return localAudioURL
        }
        return audioURL.flatMap(URL.init(string:))
    }

    /// Same rule for video: the file we still hold beats the network copy.
    var playableVideoURL: URL? {
        if let localVideoURL, FileManager.default.fileExists(atPath: localVideoURL.path) {
            return localVideoURL
        }
        return videoURL.flatMap(URL.init(string:))
    }

    /// One-line description used for reply snippets & list previews.
    var snippetText: String {
        switch kind {
        case .text, .emoji: return text
        case .file:         return "📄 \(fileName ?? "Attachment")"
        case .photo:        return "📷 Photo"
        case .video:        return "📹 Video"
        case .carousel:     return "🖼 \(carouselItems.count) items"
        case .audio:        return "🎤 Audio message"
        case .sticker:      return "🩷 Sticker"
        case .location:     return "📍 \(text.isEmpty ? "Location" : text)"
        case .poll:         return "📊 \(poll?.question ?? "Poll")"
        case .system, .timestamp: return text
        }
    }
}

struct WorldContact: Identifiable {
    let id: UUID
    var name: String
    var username: String
    var phone: String
    var avatarURL: String?
    var avatarGradient: [Color]
    var bio: String
    var city: String
    var latitude: Double
    var longitude: Double
    var distanceLabel: String
    var etaLabel: String

    init(id: UUID = UUID(), name: String, username: String, phone: String,
         avatarURL: String? = nil,
         avatarGradient: [Color] = [Color(hex: "26303F"), Color(hex: "141821")],
         bio: String = "", city: String = "",
         latitude: Double = 33.5731, longitude: Double = -7.5898,
         distanceLabel: String = "23 km", etaLabel: String = "36 min") {
        self.id = id; self.name = name; self.username = username; self.phone = phone
        self.avatarURL = avatarURL; self.avatarGradient = avatarGradient
        self.bio = bio; self.city = city
        self.latitude = latitude; self.longitude = longitude
        self.distanceLabel = distanceLabel; self.etaLabel = etaLabel
    }
}

struct WorldCircle: Identifiable {
    let id: UUID
    var name: String
    var memberIDs: [UUID]
    var colorHex: String

    init(id: UUID = UUID(), name: String, memberIDs: [UUID], colorHex: String = "3A3A3C") {
        self.id = id; self.name = name; self.memberIDs = memberIDs; self.colorHex = colorHex
    }
}

/// A marketplace (or, later, delivery/ride) reference card pinned to a thread —
/// the buyer and seller both see what the conversation is about. `listingID` is
/// parsed from the backend `refId` when `kind == "listing"`, so a tap can open
/// the live listing; the rest is the pre-rendered card.
struct WorldListingContext: Equatable {
    var kind: String
    var listingID: UUID?
    var title: String
    var subtitle: String?
    var imageURL: String?
}

struct WorldConversation: Identifiable {
    let id: UUID
    var contactID: UUID?
    var circleID: UUID?
    var title: String
    var preview: String
    var timeAgo: String
    var unread: Int
    var isGroup: Bool
    var pinned: Bool
    var avatarURL: String?
    var avatarGradient: [Color]
    var messages: [WorldMessage]
    var filterBadge: String?
    /// Used to float threads to the top when you send or receive a message.
    var lastActivityAt: Date
    /// Chat wallpaper chosen in the contact's Backgrounds tab.
    var background: WorldChatBackground
    /// The listing (or other vertical object) this thread was started from, if any.
    var listingContext: WorldListingContext?

    init(id: UUID = UUID(), contactID: UUID? = nil, circleID: UUID? = nil,
         title: String, preview: String, timeAgo: String, unread: Int = 0,
         isGroup: Bool = false, pinned: Bool = false, avatarURL: String? = nil,
         avatarGradient: [Color] = [Color(hex: "26303F"), Color(hex: "141821")],
         messages: [WorldMessage] = [], filterBadge: String? = nil,
         lastActivityAt: Date = Date(), background: WorldChatBackground = .none,
         listingContext: WorldListingContext? = nil) {
        self.id = id; self.contactID = contactID; self.circleID = circleID
        self.title = title; self.preview = preview; self.timeAgo = timeAgo
        self.unread = unread; self.isGroup = isGroup; self.pinned = pinned
        self.avatarURL = avatarURL; self.avatarGradient = avatarGradient
        self.messages = messages; self.filterBadge = filterBadge
        self.lastActivityAt = lastActivityAt; self.background = background
        self.listingContext = listingContext
    }
}

/// Steps of the WhatsApp-style My World first-run setup (own phone-verified
/// identity, separate from the app/social account). Design stays GojoGo.
enum WorldSetupStep: Int, Comparable {
    case intro       // onboarding pages presenting My World
    case phone       // enter phone number
    case code        // 6-digit verification code
    case profile     // World display name + photo

    static func < (a: WorldSetupStep, b: WorldSetupStep) -> Bool { a.rawValue < b.rawValue }
}

/// Modal sheet slot for the My World list (non-immersive). Poll & Send-Later are
/// shown as in-view overlays instead, because UIKit sheets don't present reliably
/// over the immersive chat.
enum WorldSheetKind: Int, Identifiable {
    case newMessage
    case settings
    /// Phase 2f. These ride the same single binding as the two above rather than
    /// getting booleans of their own — `WorldSheetHost` is the one owner of
    /// GojoMessages modals, and a second presenter attached to a live screen
    /// silently swallows the first.
    case composer
    case circles
    case profile
    var id: Int { rawValue }
}

extension String {
    /// Nil for empty / whitespace-only strings, so optional chaining can skip them.
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

/// One image shared in a thread, wherever its bytes live.
struct WorldChatPhoto: Identifiable {
    /// Stable across reloads: the message it came from plus its slot in a carousel.
    var id: String { "\(messageID)-\(index)" }
    let messageID: UUID
    let index: Int
    var data: Data?
    var url: String?
    var isVideo: Bool
}

/// Who you're talking to, assembled from the live conversation's participant, the
/// person's public GojoGo profile, and what the thread itself contains. Nil-safe:
/// each part fills in as it resolves, so the view never waits on all of them.
struct WorldContactProfile {
    var conversationID: UUID
    var name: String
    var handle: String?
    var avatarURL: String?
    var phone: String?
    var bio: String = ""
    var postCount: Int = 0
    var followerCount: Int = 0
    /// Members of a group thread (empty for 1:1).
    var members: [WorldContactMember] = []
    var isGroup: Bool = false
}

struct WorldContactMember: Identifiable {
    let id: UUID
    var name: String
    var handle: String?
    var avatarURL: String?
    var isYou: Bool
}

/// Selectable chat wallpaper for a My World conversation (mirrors iMessage Backgrounds).
enum WorldChatBackground: Hashable, Identifiable {
    case none, sky, water, aurora, dusk, bloom, graphite
    /// A picture the reader chose, held on this device and named by its file.
    /// The image itself never leaves the phone — a wallpaper is a fact about
    /// how you like to look at a conversation, not part of the conversation.
    case photo(String)

    /// The built-in choices, in the order the picker shows them. Replaces
    /// `CaseIterable`, which cannot enumerate a case that carries a value.
    static let presets: [WorldChatBackground] =
        [.none, .sky, .water, .aurora, .dusk, .bloom, .graphite]

    var id: String { rawValue }

    var photoName: String? {
        if case .photo(let name) = self { return name }
        return nil
    }

    var title: String {
        switch self {
        case .none:     return "None"
        case .sky:      return "Sky"
        case .water:    return "Water"
        case .aurora:   return "Aurora"
        case .dusk:     return "Dusk"
        case .bloom:    return "Bloom"
        case .graphite: return "Graphite"
        case .photo:    return "Photo"
        }
    }

    /// Gradient stops for the wallpaper (empty = not a gradient: either the
    /// plain page background, or a picture that draws itself).
    var gradient: [Color] {
        switch self {
        case .none, .photo: return []
        case .sky:      return [Color(hex: "2E5B9E"), Color(hex: "8AB6E8"), Color(hex: "E7B98F")]
        case .water:    return [Color(hex: "0B4F6C"), Color(hex: "1B98C4"), Color(hex: "8FD3E8")]
        case .aurora:   return [Color(hex: "0B2A3A"), Color(hex: "1D7A6E"), Color(hex: "3AC0E0")]
        case .dusk:     return [Color(hex: "3A1C5A"), Color(hex: "8E3B76"), Color(hex: "E8865A")]
        case .bloom:    return [Color(hex: "F58AA8"), Color(hex: "F6B078"), Color(hex: "FBD9A0")]
        case .graphite: return [Color(hex: "1A1A1C"), Color(hex: "2C2C2E"), Color(hex: "3A3A3C")]
        }
    }

    /// Whether the wallpaper is bright enough that bubbles/labels need extra contrast.
    var isLight: Bool {
        switch self {
        case .bloom: return true
        default:     return false
        }
    }

    /// Whether anything is behind the thread at all — which decides whether the
    /// header and composer stay opaque or step back and let it through.
    var isDecorated: Bool {
        if case .none = self { return false }
        return true
    }

    // MARK: Wire / storage form

    var rawValue: String {
        switch self {
        case .none:     return "none"
        case .sky:      return "sky"
        case .water:    return "water"
        case .aurora:   return "aurora"
        case .dusk:     return "dusk"
        case .bloom:    return "bloom"
        case .graphite: return "graphite"
        case .photo(let name): return "photo:" + name
        }
    }

    init?(rawValue: String) {
        if rawValue.hasPrefix("photo:") {
            let name = String(rawValue.dropFirst("photo:".count))
            guard !name.isEmpty else { return nil }
            self = .photo(name)
            return
        }
        switch rawValue {
        case "none":     self = .none
        case "sky":      self = .sky
        case "water":    self = .water
        case "aurora":   self = .aurora
        case "dusk":     self = .dusk
        case "bloom":    self = .bloom
        case "graphite": self = .graphite
        default:         return nil
        }
    }
}

/// Shared iMessage palette for My World — adapts with the app theme.
enum IMColor {
    static let blue = Color(dark: "0A84FF", light: "007AFF")
    static let bubbleGray = Color(dark: "262629", light: "E9E9EB")
    static let secondary = Color(dark: "8E8E93", light: "8A8A8E")
    static let chrome = Color(dark: "2C2C2E", light: "EAEAEE")
    static let separator = Color(dark: "38383A", light: "C6C6C8")
    static let inputFill = Color(dark: "1C1C1E", light: "FFFFFF")
    /// Page background (iMessage: pure black / pure white).
    static let bg = Color(dark: "000000", light: "FFFFFF")
    /// Primary label on the page / in incoming bubbles.
    static let label = Color(dark: "FFFFFF", light: "0A0A0A")
    /// Sheet backdrop for My World sheets.
    static let sheetBG = Color(dark: "171719", light: "F2F2F7")
}

// MARK: - GojoDelivery (food delivery · Uber Eats-style)

enum DeliveryOrderStatus: Int, Equatable, Comparable {
    case confirmed
    case preparing
    case courierToRestaurant
    case delivering
    case delivered

    static func < (lhs: DeliveryOrderStatus, rhs: DeliveryOrderStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .confirmed:           return "Order confirmed"
        case .preparing:           return "Preparing your food"
        case .courierToRestaurant: return "Courier picking up"
        case .delivering:          return "On the way"
        case .delivered:           return "Delivered"
        }
    }

    var detail: String {
        switch self {
        case .confirmed:           return "The restaurant received your order."
        case .preparing:           return "The kitchen is on it."
        case .courierToRestaurant: return "Your courier is heading to the restaurant."
        case .delivering:          return "Your food is on its way to you."
        case .delivered:           return "Enjoy your meal!"
        }
    }

    /// The same states, said to somebody who is walking to the counter
    /// themselves (Phase 4 M4). The six words on the wire did not change — this
    /// is the rendering of them that a collection needs, and it is why the
    /// order carries its fulfilment kind rather than a parallel set of statuses.
    ///
    /// A pickup only ever reaches three of these: the two courier states belong
    /// to a journey nobody is making.
    var pickupLabel: String {
        switch self {
        case .confirmed: return "Order confirmed"
        case .preparing: return "Preparing your order"
        case .delivered: return "Collected"
        default:         return "Ready to collect"
        }
    }

    var pickupDetail: String {
        switch self {
        case .confirmed: return "The restaurant received your order."
        case .preparing: return "We'll tell you the moment it's ready."
        case .delivered: return "Enjoy your meal!"
        default:         return "Show your code at the counter."
        }
    }
}

struct DeliveryMenuItem: Identifiable {
    let id: UUID
    var name: String
    var detail: String
    var price: Double
    var imageURL: String?
    var popular: Bool

    init(id: UUID = UUID(), name: String, detail: String, price: Double,
         imageURL: String? = nil, popular: Bool = false) {
        self.id = id; self.name = name; self.detail = detail
        self.price = price; self.imageURL = imageURL; self.popular = popular
    }
}

struct DeliveryMenuSection: Identifiable {
    let id: UUID
    var name: String
    var items: [DeliveryMenuItem]

    init(id: UUID = UUID(), name: String, items: [DeliveryMenuItem]) {
        self.id = id; self.name = name; self.items = items
    }
}

struct DeliveryRestaurant: Identifiable {
    let id: UUID
    var name: String
    var cuisine: String
    var rating: Double
    var reviews: String
    var etaMinutes: Int
    var feeLabel: String
    /// What the delivery fee actually is, in cents — `feeLabel` is its display
    /// form. The server prices the order, so this only drives the cart preview.
    var feeCents: Int
    var imageURL: String?
    var tags: [String]
    var promo: String?
    var categories: [String]
    var menu: [DeliveryMenuSection]
    /// The page the owner arranged above the menu (SPECS §9). Empty for every
    /// restaurant nobody has arranged one for, which renders exactly the screen
    /// this app rendered before storefronts existed.
    var storefront: [StorefrontBlock]
    var latitude: Double
    var longitude: Double
    /// Whether you can collect in store (Phase 4 M4). False for every sample
    /// restaurant and for any backend that predates collection, which is the
    /// right answer in both cases: the choice is simply not offered.
    var offersPickup: Bool
    /// What collecting promises, when it is offered — the kitchen's own pickup
    /// time, which has no courier's journey inside it.
    var pickupEtaMinutes: Int
    /// Where to walk to, when that is not simply the restaurant's address.
    var pickupAddress: String
    /// Whether they're open right now (Phase 4 M6). The server's answer, read
    /// in the restaurant's own timezone — this app doesn't know their zone, and
    /// a card that says "open" over a kitchen that will refuse the checkout is
    /// worse than one that says "closed". Defaults true, which is what every
    /// restaurant was before hours existed and what SampleData still is.
    var openNow: Bool

    init(id: UUID = UUID(), name: String, cuisine: String, rating: Double,
         reviews: String, etaMinutes: Int, feeLabel: String, feeCents: Int = 149,
         imageURL: String? = nil,
         tags: [String] = [], promo: String? = nil, categories: [String] = [],
         menu: [DeliveryMenuSection] = [], storefront: [StorefrontBlock] = [],
         latitude: Double = 33.5731, longitude: Double = -7.5898,
         offersPickup: Bool = false, pickupEtaMinutes: Int? = nil,
         pickupAddress: String = "", openNow: Bool = true) {
        self.id = id; self.name = name; self.cuisine = cuisine
        self.rating = rating; self.reviews = reviews; self.etaMinutes = etaMinutes
        self.feeLabel = feeLabel; self.feeCents = feeCents
        self.imageURL = imageURL; self.tags = tags
        self.promo = promo; self.categories = categories; self.menu = menu
        self.storefront = storefront
        self.latitude = latitude; self.longitude = longitude
        self.offersPickup = offersPickup
        self.pickupEtaMinutes = pickupEtaMinutes ?? etaMinutes
        self.pickupAddress = pickupAddress
        self.openNow = openNow
    }
}

/// A saved delivery address (backed by the `delivery` module).
struct DeliveryAddress: Identifiable, Equatable {
    let id: UUID
    var label: String
    var line1: String
    var note: String
    var latitude: Double?
    var longitude: Double?
    var isDefault: Bool

    init(id: UUID = UUID(), label: String, line1: String, note: String = "",
         latitude: Double? = nil, longitude: Double? = nil, isDefault: Bool = false) {
        self.id = id; self.label = label; self.line1 = line1; self.note = note
        self.latitude = latitude; self.longitude = longitude; self.isDefault = isDefault
    }

    /// "Home · 12 Rue Atlas"
    var display: String { line1.isEmpty ? label : "\(label) · \(line1)" }

    /// House / office / pin, picked from the label the user chose.
    var icon: String {
        switch label.lowercased() {
        case "home":  return "house.fill"
        case "work", "office": return "building.2.fill"
        default:      return "mappin.circle.fill"
        }
    }
}

struct DeliveryCartLine: Identifiable {
    var id: UUID { item.id }
    var item: DeliveryMenuItem
    var qty: Int
    /// Which kitchen this line belongs to (Phase 4 M3). A cart can now span
    /// restaurants, so a line has to carry its own — the cart-level id it used
    /// to be read from now names only the first one.
    var merchantID: UUID
    /// Copied at add time so the checkout can group under a name without
    /// holding the catalog: a restaurant you added from an hour ago may not be
    /// in this session's browse results any more.
    var merchantName: String
}

struct DeliveryCourier: Identifiable {
    let id: UUID
    var name: String
    var rating: Double
    var deliveries: Int
    var vehicle: String
    var avatarURL: String?

    init(id: UUID = UUID(), name: String, rating: Double, deliveries: Int,
         vehicle: String, avatarURL: String? = nil) {
        self.id = id; self.name = name; self.rating = rating
        self.deliveries = deliveries; self.vehicle = vehicle; self.avatarURL = avatarURL
    }
}

struct DeliveryPastOrder: Identifiable {
    let id: UUID
    var restaurantName: String
    var imageURL: String?
    var itemsSummary: String
    var totalLabel: String
    var dateLabel: String
    var rating: Int

    init(id: UUID = UUID(), restaurantName: String, imageURL: String? = nil,
         itemsSummary: String, totalLabel: String, dateLabel: String, rating: Int = 0) {
        self.id = id; self.restaurantName = restaurantName; self.imageURL = imageURL
        self.itemsSummary = itemsSummary; self.totalLabel = totalLabel
        self.dateLabel = dateLabel; self.rating = rating
    }
}

// MARK: - Partner (Become a driver / delivery partner)

/// A side of the marketplace the user can sign up to work on.
enum PartnerRole: String, Codable, Equatable, CaseIterable {
    case driver     // GojoTravel
    case courier    // GojoDelivery ("delivery guy")

    /// Amount, in USD, held as a good-conduct stake before the partner can work.
    static let stakeAmount: Double = 30

    var title: String { self == .driver ? "Driver" : "Delivery Partner" }
    var ctaTitle: String { self == .driver ? "Become a driver" : "Become a delivery partner" }
    var service: String { self == .driver ? "GojoTravel" : "GojoDelivery" }
    var wordmarkTrailing: String { self == .driver ? "travel" : "delivery" }
    var icon: String { self == .driver ? "car.fill" : "bag.fill" }
    var earner: String { self == .driver ? "riders" : "customers" }
    var jobNoun: String { self == .driver ? "trip" : "delivery" }
}

/// Stage of the become-a-partner flow.
enum PartnerOnboardingStep: Int, Equatable, Comparable {
    case rules      // rules / how it works, tap "I agree"
    case stake      // pay the $30 good-conduct stake
    case kyc        // upload ID + (driver) vehicle papers
    case done       // process complete

    static func < (a: PartnerOnboardingStep, b: PartnerOnboardingStep) -> Bool {
        a.rawValue < b.rawValue
    }
}

// `IDDocumentType` used to live here — the app asked which document you were
// holding and let you tap a tile to say you'd photographed it. Sumsub asks that
// question now, inside its own flow, against the list of documents its level
// actually accepts in your country. Ours was always a guess.

enum CourierVehicle: String, CaseIterable, Identifiable {
    case onFeet = "On feet"
    case bicycle = "Bicycle"
    case scooter = "Scooter"
    case motorbike = "Motorbike"
    case car = "Car"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .onFeet: return "figure.walk"
        case .bicycle: return "bicycle"
        case .scooter: return "scooter"
        case .motorbike: return "figure.outdoor.cycle"
        case .car: return "car.fill"
        }
    }
}

/// What a driver drives. A trottinette (kick/e-scooter) needs no licence or
/// vehicle registration, so its KYC is identity-only.
enum DriverVehicle: String, CaseIterable, Identifiable {
    case car = "Car"
    case motorcycle = "Motorcycle"
    /// Called a trottinette in the country this app was written in, and a
    /// kickscooter, e-scooter or patinete elsewhere. "E-scooter" is the label
    /// most riders will recognise wherever they are; the case keeps its original
    /// name because renaming it would say nothing new about the vehicle.
    case trottinette = "E-scooter"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .car:         return "car.fill"
        case .motorcycle:  return "figure.outdoor.cycle"
        case .trottinette: return "scooter"
        }
    }
    /// Cars & motorcycles need a licence + registration; e-scooters don't.
    var requiresLicense: Bool { self != .trottinette }

    /// The same vehicle in `dispatch`'s vocabulary — what the server matches a
    /// ride on. Two enums in two places on purpose: this one is what a person
    /// picks from, that one is what a search filters by, and they will not stay
    /// the same list forever.
    var dispatchCategory: String {
        switch self {
        case .car:         return "CAR"
        case .motorcycle:  return "SCOOTER"
        case .trottinette: return "BIKE"
        }
    }
}

/// KYC + vehicle data captured during onboarding.
/// The partner application's *local* half.
///
/// Identity is deliberately absent. Proving who someone is belongs to the IDV
/// vendor and to the backend's `kyc` module — the app used to collect a name, a
/// document number and two "captured" checkboxes that nothing ever verified, and
/// keeping that alongside a real check would be worse than useless: it would
/// look like a second opinion.
///
/// What's left is the vehicle side, which is still the local prototype waiting
/// on the Phase 3 `dispatch` module (SPECS §4).
struct PartnerApplication: Equatable {
    var role: PartnerRole

    // Driver — vehicle type + (for car/motorcycle) papers
    var driverVehicle: DriverVehicle = .car
    var licenseNumber: String = ""
    var vehicleMake: String = ""
    var vehicleModel: String = ""
    var vehicleYear: String = ""
    var vehicleColor: String = ""
    var plate: String = ""
    /// Where the plate was issued, ISO 3166-1 alpha-2. Defaulted from the device
    /// and never assumed: somebody who moved still drives a car registered where
    /// they came from, and a plate belongs to the car rather than to the phone.
    var vehicleCountry: String = VehicleRegistry.deviceCountry
    /// The state or province that issued it, where one did. Empty everywhere
    /// plates are national — which is most of the world, and why the form only
    /// asks for this in the countries whose plates carry one.
    var vehicleRegion: String = ""
    /// `yyyy-MM-dd`. Papers expire on a day, and the server flags a vehicle
    /// whose earlier date has passed (plus a grace period).
    var registrationExpiresOn: String = ""
    var insuranceExpiresOn: String = ""

    // Courier — vehicle type
    var vehicleType: CourierVehicle = .motorbike

    /// Whether the fields somebody *types* on this form are filled in.
    ///
    /// Documents are deliberately not part of this. They used to be — three
    /// `…Captured` booleans that a tile toggled and nothing ever set once the
    /// tiles became real uploads, which left this property permanently false and
    /// the Submit button permanently grey however carefully the form was filled
    /// in. Whether a paper exists is the server's answer now (`missingDocuments`
    /// on the application and on the vehicle), and `AppState.partnerKYCComplete`
    /// is where the two halves meet.
    var vehicleDetailsComplete: Bool {
        switch role {
        case .driver:
            // Trottinettes are identity-only — no licence or vehicle papers.
            guard driverVehicle.requiresLicense else { return true }
            return !licenseNumber.trimmingCharacters(in: .whitespaces).isEmpty
                && !vehicleMake.trimmingCharacters(in: .whitespaces).isEmpty
                && !vehicleModel.trimmingCharacters(in: .whitespaces).isEmpty
                && !plate.trimmingCharacters(in: .whitespaces).isEmpty
                // A plate without the country that issued it isn't an
                // identifier: the same string is a different car elsewhere.
                && !vehicleCountry.isEmpty
                // …and in the countries that issue plates by state, which state
                // is part of the plate rather than an address.
                && (!VehicleRegistry.rules(for: vehicleCountry).asksForSubdivision
                    || !vehicleRegion.trimmingCharacters(in: .whitespaces).isEmpty)
                // The server refuses a vehicle whose papers have no end date —
                // it can't tell a current registration from a lapsed one — so
                // the two date fields are as required as the plate is.
                && !registrationExpiresOn.trimmingCharacters(in: .whitespaces).isEmpty
                && !insuranceExpiresOn.trimmingCharacters(in: .whitespaces).isEmpty
        case .courier:
            return true
        }
    }
}

/// Phase of a live job while the partner is online.
enum PartnerJobPhase: Equatable {
    case idle           // online, waiting for offers
    case offer          // an incoming request is on screen
    case toPickup       // accepted, heading to pickup / restaurant
    case toDropoff      // picked up, heading to the customer
    case completed      // dropped off — rate + collect
}

/// A ride or delivery offered to an online partner.
struct PartnerJob: Identifiable, Equatable {
    let id: UUID
    var role: PartnerRole
    var customerName: String
    var pickupName: String
    var pickupSubtitle: String
    var dropoffName: String
    var dropoffSubtitle: String
    var distanceKm: Double
    var minutes: Int
    var fare: Double
    var customerAvatarURL: String?
    // Map coordinates for the live route guide.
    var originLat: Double    // where the partner starts (heading to pickup)
    var originLon: Double
    var pickupLat: Double
    var pickupLon: Double
    var dropoffLat: Double
    var dropoffLon: Double
    /// The `travel` ride behind this card, when the job is a real RIDE offer —
    /// what makes the fare readable and a counteroffer possible. Nil for demo
    /// jobs and deliveries.
    var rideId: UUID?

    init(id: UUID = UUID(), role: PartnerRole, customerName: String,
         pickupName: String, pickupSubtitle: String,
         dropoffName: String, dropoffSubtitle: String,
         distanceKm: Double, minutes: Int, fare: Double,
         customerAvatarURL: String? = nil,
         originLat: Double = 33.5731, originLon: Double = -7.5898,
         pickupLat: Double = 33.5731, pickupLon: Double = -7.5898,
         dropoffLat: Double = 33.5731, dropoffLon: Double = -7.5898,
         rideId: UUID? = nil) {
        self.id = id; self.role = role; self.customerName = customerName
        self.pickupName = pickupName; self.pickupSubtitle = pickupSubtitle
        self.dropoffName = dropoffName; self.dropoffSubtitle = dropoffSubtitle
        self.distanceKm = distanceKm; self.minutes = minutes; self.fare = fare
        self.customerAvatarURL = customerAvatarURL
        self.originLat = originLat; self.originLon = originLon
        self.pickupLat = pickupLat; self.pickupLon = pickupLon
        self.dropoffLat = dropoffLat; self.dropoffLon = dropoffLon
        self.rideId = rideId
    }

    /// A dispatch offer carries no fare — the money belongs to the vertical
    /// that asked, and dispatch never sees it. So an unpriced job says so
    /// instead of rendering "$0.00", which would read as free work.
    var fareLabel: String { fare > 0 ? String(format: "$%.2f", fare) : "—" }

    var isPriced: Bool { fare > 0 }
    var distanceLabel: String { String(format: "%.1f km", distanceKm) }
}

// MARK: - Profile Home (customizable profile canvas)

/// The kinds of blocks a user can stack to compose their profile Home tab.
enum ProfileHomeBlockKind: String, Codable, CaseIterable, Identifiable {
    case heading    // big title + optional subtitle
    case banner     // wide cover — a picture or video
    case text       // a freeform note
    case featured   // one post shown as a large hero
    case media      // free-standing pictures & videos (not tied to a post)
    case gallery    // a titled set of posts in a grid
    case link       // a tappable link/CTA button

    var id: String { rawValue }

    var label: String {
        switch self {
        case .heading:  return "Heading"
        case .banner:   return "Banner"
        case .text:     return "Text note"
        case .featured: return "Featured post"
        case .media:    return "Photos & video"
        case .gallery:  return "Gallery"
        case .link:     return "Link button"
        }
    }

    var icon: String {
        switch self {
        case .heading:  return "textformat.size"
        case .banner:   return "photo.on.rectangle.angled"
        case .text:     return "text.alignleft"
        case .featured: return "star.square"
        case .media:    return "photo.stack"
        case .gallery:  return "square.grid.2x2"
        case .link:     return "link"
        }
    }

    var blurb: String {
        switch self {
        case .heading:  return "A section title to break up your page"
        case .banner:   return "A wide cover photo or video up top"
        case .text:     return "Say something in your own words"
        case .featured: return "Spotlight a single post, big and bold"
        case .media:    return "Drop in pictures and clips — no post needed"
        case .gallery:  return "Curate a set of posts your way"
        case .link:     return "Send people anywhere with one tap"
        }
    }
}

/// A single picture or video used by Banner / Photos-&-video blocks.
/// Images come from the sample library (`imageURL`) or an imported photo
/// (`imageData`); videos reference a bundled clip (`videoURL`) + poster.
struct ProfileHomeMedia: Identifiable, Equatable, Codable {
    var id: UUID
    var imageURL: String?
    var imageData: Data?
    var videoURL: String?
    var posterURL: String?

    init(id: UUID = UUID(), imageURL: String? = nil, imageData: Data? = nil,
         videoURL: String? = nil, posterURL: String? = nil) {
        self.id = id; self.imageURL = imageURL; self.imageData = imageData
        self.videoURL = videoURL; self.posterURL = posterURL
    }

    var isVideo: Bool { videoURL != nil }

    /// Whether two media refer to the same underlying asset (ignores id).
    func sameAsset(as other: ProfileHomeMedia) -> Bool {
        imageURL == other.imageURL && videoURL == other.videoURL && imageData == other.imageData
    }
}

/// Visual treatment applied to heading / link blocks.
enum ProfileHomeStyle: String, Codable, CaseIterable, Identifiable {
    case plain      // bare text
    case card       // glass card
    case accent     // filled ink banner / CTA

    var id: String { rawValue }
    var label: String {
        switch self {
        case .plain:  return "Plain"
        case .card:   return "Card"
        case .accent: return "Accent"
        }
    }
}

/// One composable block on the profile Home tab.
struct ProfileHomeBlock: Identifiable, Equatable, Codable {
    var id: UUID
    var kind: ProfileHomeBlockKind
    var title: String
    var text: String
    var url: String
    var postIDs: [UUID]
    var media: [ProfileHomeMedia]   // banner / photos-&-video blocks
    var columns: Int                // gallery / media: 1…3
    var style: ProfileHomeStyle

    init(id: UUID = UUID(), kind: ProfileHomeBlockKind,
         title: String = "", text: String = "", url: String = "",
         postIDs: [UUID] = [], media: [ProfileHomeMedia] = [],
         columns: Int = 3, style: ProfileHomeStyle = .card) {
        self.id = id; self.kind = kind; self.title = title; self.text = text
        self.url = url; self.postIDs = postIDs; self.media = media
        self.columns = columns; self.style = style
    }

    // Resilient decoding so layouts saved by older builds (before `media`)
    // still load instead of throwing and wiping the whole session.
    enum CodingKeys: String, CodingKey {
        case id, kind, title, text, url, postIDs, media, columns, style
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(ProfileHomeBlockKind.self, forKey: .kind)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        postIDs = try c.decodeIfPresent([UUID].self, forKey: .postIDs) ?? []
        media = try c.decodeIfPresent([ProfileHomeMedia].self, forKey: .media) ?? []
        columns = try c.decodeIfPresent(Int.self, forKey: .columns) ?? 3
        style = try c.decodeIfPresent(ProfileHomeStyle.self, forKey: .style) ?? .card
    }
}
