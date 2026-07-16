import SwiftUI

// MARK: - Navigation enums

enum AppTab: Hashable { case home, watch, madeleine, travel, economy, search }

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
        return false
    }

    init(id: UUID = UUID(), author: String, meta: String,
         avatarGradient: [Color], avatarURL: String? = nil,
         imageURL: String? = nil, imageData: Data? = nil,
         videoURL: String? = nil,
         imageAspect: CGFloat = 1.0, text: String? = nil,
         showFollow: Bool = false, liked: Bool = false,
         bookmarked: Bool = false, following: Bool = false,
         likeCount: Int = 0, commentCount: Int = 0,
         isHalfWidth: Bool = false) {
        self.id = id; self.author = author; self.meta = meta
        self.avatarGradient = avatarGradient; self.avatarURL = avatarURL
        self.imageURL = imageURL; self.imageData = imageData
        self.videoURL = videoURL
        self.imageAspect = imageAspect; self.text = text
        self.showFollow = showFollow; self.liked = liked
        self.bookmarked = bookmarked; self.following = following
        self.likeCount = likeCount; self.commentCount = commentCount
        self.isHalfWidth = isHalfWidth
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
