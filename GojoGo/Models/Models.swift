import SwiftUI

// MARK: - Navigation enums

/// Top-level app section: private social (My World) vs public superapp (Collections).
enum AppNavMode: String, Hashable {
    case myWorld
    case collections
}

enum AppTab: Hashable { case home, watch, madeleine, travel, delivery, economy, search }

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
    var name: String = "Jad"
    var handle: String = "jad"
    var birthYear: Int = 2004
    var interests: [String] = []
    var avatarGradient: [Color] = [Color(hex: "26303F"), Color(hex: "141821")]
    var avatarURL: String? = "https://picsum.photos/seed/jad-avatar/200/200"
    var followingCount: Int = 1204
    var followerCount: Int = 8600
    var postCount: Int = 3
    var bio: String = "Building on gojogo."
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

// MARK: - Content models

struct StoryFrame: Identifiable, Equatable {
    let id: UUID
    var imageURL: String?
    var imageData: Data?
    var seen: Bool

    init(id: UUID = UUID(), imageURL: String? = nil, imageData: Data? = nil, seen: Bool = false) {
        self.id = id
        self.imageURL = imageURL
        self.imageData = imageData
        self.seen = seen
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

    var seen: Bool {
        frames.isEmpty || frames.allSatisfy(\.seen)
    }

    var imageURL: String? { frames.first?.imageURL }
    var imageData: Data? { frames.first?.imageData }
    var hasMedia: Bool { frames.contains { $0.imageURL != nil || $0.imageData != nil } }

    init(id: UUID = UUID(), name: String, letter: String, gradient: [Color],
         frames: [StoryFrame] = [], isYou: Bool = false) {
        self.id = id; self.name = name; self.letter = letter
        self.gradient = gradient; self.frames = frames; self.isYou = isYou
    }

    /// Convenience for a single-frame story.
    init(id: UUID = UUID(), name: String, letter: String, gradient: [Color],
         imageURL: String? = nil, imageData: Data? = nil,
         seen: Bool = false, isYou: Bool = false) {
        var frames: [StoryFrame] = []
        if imageURL != nil || imageData != nil {
            frames = [StoryFrame(imageURL: imageURL, imageData: imageData, seen: seen)]
        }
        self.init(id: id, name: name, letter: letter, gradient: gradient,
                  frames: frames, isYou: isYou)
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
    /// Extra slides for a multi-photo / video carousel post (includes the first slide).
    var mediaItems: [PostMediaItem]
    var imageAspect: CGFloat   // height / width hint for layout
    var text: String?
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
         mediaItems: [PostMediaItem] = [],
         imageAspect: CGFloat = 1.0, text: String? = nil,
         showFollow: Bool = false, liked: Bool = false,
         bookmarked: Bool = false, following: Bool = false,
         likeCount: Int = 0, commentCount: Int = 0,
         isHalfWidth: Bool = false) {
        self.id = id; self.author = author; self.meta = meta
        self.avatarGradient = avatarGradient; self.avatarURL = avatarURL
        self.imageURL = imageURL; self.imageData = imageData
        self.videoURL = videoURL
        self.mediaItems = mediaItems
        self.imageAspect = imageAspect; self.text = text
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

struct VideoItem: Identifiable {
    let id: UUID
    let title: String
    let channel: String
    let meta: String
    let duration: String
    let thumbGradient: [Color]
    var thumbURL: String?
    var thumbData: Data?
    var videoURL: String?
    var likes: Int
    var liked: Bool
    var saved: Bool

    init(id: UUID = UUID(), title: String, channel: String, meta: String,
         duration: String, thumbGradient: [Color], thumbURL: String? = nil,
         thumbData: Data? = nil, videoURL: String? = nil,
         likes: Int = 0, liked: Bool = false, saved: Bool = false) {
        self.id = id; self.title = title; self.channel = channel; self.meta = meta
        self.duration = duration; self.thumbGradient = thumbGradient
        self.thumbURL = thumbURL; self.thumbData = thumbData; self.videoURL = videoURL
        self.likes = likes; self.liked = liked; self.saved = saved
    }
}

struct Short: Identifiable {
    let id: UUID
    let channel: String
    let subscribers: String
    let caption: String
    let gradient: [Color]
    var imageURL: String?
    var imageData: Data?
    /// Local file or remote HTTP URL for playback.
    var videoURL: String?
    var liked: Bool
    var bookmarked: Bool
    var following: Bool
    var likeCount: Int

    init(id: UUID = UUID(), channel: String, subscribers: String, caption: String,
         gradient: [Color], imageURL: String? = nil, imageData: Data? = nil,
         videoURL: String? = nil,
         liked: Bool = false, bookmarked: Bool = false, following: Bool = false,
         likeCount: Int = 1200) {
        self.id = id; self.channel = channel; self.subscribers = subscribers
        self.caption = caption; self.gradient = gradient; self.imageURL = imageURL
        self.imageData = imageData; self.videoURL = videoURL
        self.liked = liked; self.bookmarked = bookmarked; self.following = following
        self.likeCount = likeCount
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

    init(id: UUID = UUID(), name: String, price: String, meta: String = "",
         gradient: [Color], imageURL: String? = nil, saved: Bool = false,
         category: String = "All", seller: String = "seller",
         condition: String = "Good", distance: String = "nearby",
         description: String = "") {
        self.id = id; self.name = name; self.price = price; self.meta = meta
        self.gradient = gradient; self.imageURL = imageURL; self.saved = saved
        self.category = category; self.seller = seller
        self.condition = condition; self.distance = distance
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

enum ActivityKind: String {
    case like, comment, follow, mention, order, system

    var icon: String {
        switch self {
        case .like: return "heart.fill"
        case .comment: return "bubble.right.fill"
        case .follow: return "person.fill.badge.plus"
        case .mention: return "at"
        case .order: return "bag.fill"
        case .system: return "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .like: return Color(hex: "E85D75")
        case .comment: return GGColor.blue
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

    init(id: UUID = UUID(), kind: ActivityKind, actor: String, text: String,
         timeAgo: String, read: Bool = false, avatarURL: String? = nil,
         previewURL: String? = nil) {
        self.id = id; self.kind = kind; self.actor = actor; self.text = text
        self.timeAgo = timeAgo; self.read = read; self.avatarURL = avatarURL
        self.previewURL = previewURL
    }
}

struct Comment: Identifiable, Hashable {
    let id: UUID
    let author: String
    let text: String
    var avatarURL: String?
    var liked: Bool
    var likeCount: Int
    let timeAgo: String

    init(id: UUID = UUID(), author: String, text: String,
         avatarURL: String? = nil, liked: Bool = false,
         likeCount: Int = 0, timeAgo: String = "just now") {
        self.id = id; self.author = author; self.text = text
        self.avatarURL = avatarURL; self.liked = liked
        self.likeCount = likeCount; self.timeAgo = timeAgo
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

    var isVideo: Bool {
        videoURL != nil || kind == .short || kind == .longForm
    }

    init(id: UUID = UUID(), kind: ComposeMediaKind, imageData: Data,
         originalImageData: Data? = nil,
         durationLabel: String? = nil, audioURL: URL? = nil,
         videoURL: URL? = nil,
         trimStart: Double = 0, trimEnd: Double = 1) {
        self.id = id; self.kind = kind; self.imageData = imageData
        self.originalImageData = originalImageData ?? imageData
        self.durationLabel = durationLabel; self.audioURL = audioURL
        self.videoURL = videoURL
        self.trimStart = trimStart; self.trimEnd = trimEnd
    }
}

// MARK: - My World (private social · iMessage-inspired)

enum WorldMessageKind {
    case text
    case emoji
    case file
    case photo
    case video
    case carousel
    case audio
    case location
    case system
    case timestamp
}

/// One slide inside a chat media carousel (photo and/or video).
struct WorldCarouselItem: Identifiable, Equatable {
    let id: UUID
    var imageData: Data
    var isVideo: Bool
    var durationLabel: String?

    init(id: UUID = UUID(), imageData: Data, isVideo: Bool = false, durationLabel: String? = nil) {
        self.id = id; self.imageData = imageData
        self.isVideo = isVideo; self.durationLabel = durationLabel
    }
}

/// Media staged in the chat composer before sending (iMessage-style preview tray).
struct WorldPendingAttachment: Identifiable {
    let id: UUID
    var imageData: Data
    var isVideo: Bool
    var durationLabel: String?

    init(id: UUID = UUID(), imageData: Data, isVideo: Bool = false, durationLabel: String? = nil) {
        self.id = id; self.imageData = imageData
        self.isVideo = isVideo; self.durationLabel = durationLabel
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
    var imageData: Data?
    var durationLabel: String?
    var senderName: String?
    var carouselItems: [WorldCarouselItem]

    init(id: UUID = UUID(), kind: WorldMessageKind = .text, text: String,
         fromUser: Bool = false, fileName: String? = nil, fileMeta: String? = nil,
         readLabel: String? = nil, imageData: Data? = nil, durationLabel: String? = nil,
         senderName: String? = nil, carouselItems: [WorldCarouselItem] = []) {
        self.id = id; self.kind = kind; self.text = text; self.fromUser = fromUser
        self.fileName = fileName; self.fileMeta = fileMeta; self.readLabel = readLabel
        self.imageData = imageData; self.durationLabel = durationLabel
        self.senderName = senderName; self.carouselItems = carouselItems
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

    init(id: UUID = UUID(), contactID: UUID? = nil, circleID: UUID? = nil,
         title: String, preview: String, timeAgo: String, unread: Int = 0,
         isGroup: Bool = false, pinned: Bool = false, avatarURL: String? = nil,
         avatarGradient: [Color] = [Color(hex: "26303F"), Color(hex: "141821")],
         messages: [WorldMessage] = [], filterBadge: String? = nil,
         lastActivityAt: Date = Date()) {
        self.id = id; self.contactID = contactID; self.circleID = circleID
        self.title = title; self.preview = preview; self.timeAgo = timeAgo
        self.unread = unread; self.isGroup = isGroup; self.pinned = pinned
        self.avatarURL = avatarURL; self.avatarGradient = avatarGradient
        self.messages = messages; self.filterBadge = filterBadge
        self.lastActivityAt = lastActivityAt
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
    var imageURL: String?
    var tags: [String]
    var promo: String?
    var categories: [String]
    var menu: [DeliveryMenuSection]
    var latitude: Double
    var longitude: Double

    init(id: UUID = UUID(), name: String, cuisine: String, rating: Double,
         reviews: String, etaMinutes: Int, feeLabel: String, imageURL: String? = nil,
         tags: [String] = [], promo: String? = nil, categories: [String] = [],
         menu: [DeliveryMenuSection] = [],
         latitude: Double = 33.5731, longitude: Double = -7.5898) {
        self.id = id; self.name = name; self.cuisine = cuisine
        self.rating = rating; self.reviews = reviews; self.etaMinutes = etaMinutes
        self.feeLabel = feeLabel; self.imageURL = imageURL; self.tags = tags
        self.promo = promo; self.categories = categories; self.menu = menu
        self.latitude = latitude; self.longitude = longitude
    }
}

struct DeliveryCartLine: Identifiable {
    var id: UUID { item.id }
    var item: DeliveryMenuItem
    var qty: Int
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
