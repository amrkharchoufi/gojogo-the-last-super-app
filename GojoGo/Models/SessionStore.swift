import SwiftUI
import UIKit

// MARK: - Disk-backed cached session (prototype — no backend yet)

enum SessionStore {
    private static let fileName = "gojogo-session.json"
    private static let flagKey = "gojogo.hasCachedSession"

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = dir.appendingPathComponent("GojoGo", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }

    static var hasCachedSession: Bool {
        UserDefaults.standard.bool(forKey: flagKey) && FileManager.default.fileExists(atPath: fileURL.path)
    }

    static func load() -> CachedSession? {
        guard hasCachedSession,
              let data = try? Data(contentsOf: fileURL),
              let session = try? JSONDecoder().decode(CachedSession.self, from: data)
        else { return nil }
        return session
    }

    static func save(_ session: CachedSession) {
        do {
            let data = try JSONEncoder().encode(session)
            try data.write(to: fileURL, options: [.atomic])
            UserDefaults.standard.set(true, forKey: flagKey)
        } catch {
            #if DEBUG
            print("SessionStore save failed: \(error)")
            #endif
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: flagKey)
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Durable local videos (survive rebuilds)

/// Stores movies under Application Support and references them by stable relative id
/// (`gojovideo:filename`) so sandbox container UUID changes don't break playback.
enum VideoLibrary {
    static let prefix = "gojovideo:"

    static var directory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = root.appendingPathComponent("GojoGo/Videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copy a picked/temp movie into durable storage. Returns a stable `gojovideo:` ref.
    static func persist(_ source: URL?) -> String? {
        guard let source else { return nil }
        if !source.isFileURL {
            return source.absoluteString
        }

        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let name = "vid-\(UUID().uuidString).\(ext)"
        let dest = directory.appendingPathComponent(name)

        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
            return prefix + name
        } catch {
            // Fall back to absolute path (may not survive reinstall).
            return source.absoluteString
        }
    }

    /// Resolve a stored ref (relative, absolute file, or http) to a playable URL string.
    static func resolve(_ stored: String?) -> String? {
        guard let stored, !stored.isEmpty else { return nil }

        if stored.hasPrefix("http://") || stored.hasPrefix("https://") {
            return SampleData.repairedVideoURL(stored)
        }

        if stored.hasPrefix(prefix) {
            let name = String(stored.dropFirst(prefix.count))
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url.absoluteString
        }

        // Legacy absolute file:// from older builds — remap by filename into App Support / Caches.
        if let url = URL(string: stored), url.isFileURL {
            let name = url.lastPathComponent
            let durable = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: durable.path) {
                return durable.absoluteString
            }
            if FileManager.default.fileExists(atPath: url.path) {
                // Still on disk under old absolute path (same install) — migrate.
                try? FileManager.default.copyItem(at: url, to: durable)
                if FileManager.default.fileExists(atPath: durable.path) {
                    return durable.absoluteString
                }
                return url.absoluteString
            }
            // Look in Caches leftover from previous helper.
            if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                let cached = caches.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: cached.path) {
                    try? FileManager.default.copyItem(at: cached, to: durable)
                    if FileManager.default.fileExists(atPath: durable.path) {
                        return durable.absoluteString
                    }
                    return cached.absoluteString
                }
            }
            return nil
        }

        return SampleData.repairedVideoURL(stored)
    }

    /// Normalize stored session values to durable refs when the file still exists.
    static func normalizeStored(_ stored: String?) -> String? {
        guard let stored, !stored.isEmpty else { return stored }
        if stored.hasPrefix(prefix) || stored.hasPrefix("http") {
            return stored.hasPrefix("http") ? SampleData.repairedVideoURL(stored) : stored
        }
        if let url = URL(string: stored), url.isFileURL {
            let name = url.lastPathComponent
            let durable = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: durable.path) {
                return prefix + name
            }
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.copyItem(at: url, to: durable)
                if FileManager.default.fileExists(atPath: durable.path) {
                    return prefix + name
                }
            }
            if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                let cached = caches.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: cached.path) {
                    try? FileManager.default.copyItem(at: cached, to: durable)
                    if FileManager.default.fileExists(atPath: durable.path) {
                        return prefix + name
                    }
                }
            }
            // File gone after rebuild — keep thumbnail but drop dead URL.
            return nil
        }
        return SampleData.repairedVideoURL(stored)
    }
}

// MARK: - Snapshot

struct CachedSession: Codable {
    var email: String
    var user: CachedUser
    var interests: [CachedInterest]
    var stories: [CachedStory]
    var posts: [CachedPost]
    var videos: [CachedVideo]
    var shorts: [CachedShort]
    var products: [CachedProduct]
    var featuredProduct: CachedProduct
    var people: [CachedPerson]
    var profilePhotos: [String]
    var savedPostIDs: [UUID]
    var comments: [CachedCommentThread]
    var chatMessages: [CachedChatMessage]
    var activeTabRaw: String
    var watchSubFeedRaw: String
}

struct CachedUser: Codable {
    var name: String
    var handle: String
    var birthYear: Int
    var interests: [String]
    var avatarGradient: [String]
    var avatarURL: String?
    var followingCount: Int
    var followerCount: Int
    var postCount: Int
    var bio: String?
    var category: String?
}

struct CachedInterest: Codable {
    var id: UUID
    var title: String
    var selected: Bool
    var x: Double
    var y: Double
    var size: Double
    var accent: [String]?
}

struct CachedStoryFrame: Codable {
    var id: UUID
    var imageURL: String?
    var imageData: Data?
    var seen: Bool
}

struct CachedStory: Codable {
    var id: UUID
    var name: String
    var letter: String
    var gradient: [String]
    var frames: [CachedStoryFrame]
    var isYou: Bool
}

struct CachedPost: Codable {
    var id: UUID
    var author: String
    var meta: String
    var avatarGradient: [String]
    var avatarURL: String?
    var imageURL: String?
    var imageData: Data?
    var videoURL: String?
    var imageAspect: Double
    var text: String?
    var showFollow: Bool
    var liked: Bool
    var bookmarked: Bool
    var following: Bool
    var likeCount: Int
    var commentCount: Int
    var isHalfWidth: Bool
}

struct CachedVideo: Codable {
    var id: UUID
    var title: String
    var channel: String
    var meta: String
    var duration: String
    var thumbGradient: [String]
    var thumbURL: String?
    var thumbData: Data?
    var videoURL: String?
    var likes: Int
    var liked: Bool
    var saved: Bool
}

struct CachedShort: Codable {
    var id: UUID
    var channel: String
    var subscribers: String
    var caption: String
    var gradient: [String]
    var imageURL: String?
    var imageData: Data?
    var videoURL: String?
    var liked: Bool
    var bookmarked: Bool
    var following: Bool
    var likeCount: Int
}

struct CachedProduct: Codable {
    var id: UUID
    var name: String
    var price: String
    var meta: String
    var gradient: [String]
    var imageURL: String?
    var saved: Bool
    var category: String?
    var seller: String?
    var condition: String?
    var distance: String?
    var description: String?
}

struct CachedPerson: Codable {
    var id: UUID
    var name: String
    var gradient: [String]
    var avatarURL: String?
    var following: Bool
}

struct CachedComment: Codable {
    var id: UUID
    var author: String
    var text: String
    var avatarURL: String?
    var liked: Bool
    var likeCount: Int
    var timeAgo: String
}

struct CachedCommentThread: Codable {
    var postID: UUID
    var comments: [CachedComment]
}

struct CachedChatMessage: Codable {
    var id: UUID
    var text: String
    var fromUser: Bool
}

// MARK: - Color hex helpers

enum SessionColor {
    static func hex(from color: Color) -> String {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        }
        return "141821"
    }

    static func colors(from hexes: [String]) -> [Color] {
        let mapped = hexes.map { Color(hex: $0) }
        return mapped.isEmpty ? [Color(hex: "26303F"), Color(hex: "141821")] : mapped
    }
}

// MARK: - Mapping

extension CachedSession {
    @MainActor
    init(snapshotting app: AppState) {
        email = app.email
        user = CachedUser(from: app.user)
        interests = app.interests.map(CachedInterest.init)
        stories = app.stories.map(CachedStory.init)
        posts = app.posts.map(CachedPost.init)
        videos = app.videos.map(CachedVideo.init)
        shorts = app.shorts.map(CachedShort.init)
        products = app.products.map(CachedProduct.init)
        featuredProduct = CachedProduct(from: app.featuredProduct)
        people = app.people.map(CachedPerson.init)
        profilePhotos = app.profilePhotos
        savedPostIDs = Array(app.savedPostIDs)
        comments = app.commentsByPost.map { CachedCommentThread(postID: $0.key, comments: $0.value.map(CachedComment.init)) }
        chatMessages = app.chatMessages.map(CachedChatMessage.init)
        activeTabRaw = {
            switch app.activeTab {
            case .home: return "home"
            case .watch: return "watch"
            case .madeleine: return "madeleine"
            case .travel: return "travel"
            case .economy: return "economy"
            case .search: return "search"
            }
        }()
        watchSubFeedRaw = app.watchSubFeed.rawValue
    }
}

extension CachedUser {
    init(from u: GGUser) {
        name = u.name; handle = u.handle; birthYear = u.birthYear
        interests = u.interests
        avatarGradient = u.avatarGradient.map(SessionColor.hex)
        avatarURL = u.avatarURL
        followingCount = u.followingCount; followerCount = u.followerCount; postCount = u.postCount
        bio = u.bio; category = u.category
    }

    func asDomain() -> GGUser {
        var u = GGUser()
        u.name = name; u.handle = handle; u.birthYear = birthYear
        u.interests = interests
        u.avatarGradient = SessionColor.colors(from: avatarGradient)
        u.avatarURL = avatarURL
        u.followingCount = followingCount; u.followerCount = followerCount; u.postCount = postCount
        u.bio = bio ?? "Building on gojogo."
        u.category = category ?? "Creator"
        return u
    }
}

extension CachedInterest {
    init(from i: Interest) {
        id = i.id; title = i.title; selected = i.selected
        x = Double(i.x); y = Double(i.y); size = Double(i.size)
        accent = i.accent?.map(SessionColor.hex)
    }

    func asDomain() -> Interest {
        Interest(id: id, title: title, selected: selected,
                 x: CGFloat(x), y: CGFloat(y), size: CGFloat(size),
                 accent: accent.map { SessionColor.colors(from: $0) })
    }
}

extension CachedStory {
    init(from s: Story) {
        id = s.id; name = s.name; letter = s.letter
        gradient = s.gradient.map(SessionColor.hex)
        frames = s.frames.map {
            CachedStoryFrame(id: $0.id, imageURL: $0.imageURL, imageData: $0.imageData, seen: $0.seen)
        }
        isYou = s.isYou
    }

    func asDomain() -> Story {
        Story(id: id, name: name, letter: letter,
              gradient: SessionColor.colors(from: gradient),
              frames: frames.map {
                  StoryFrame(id: $0.id, imageURL: $0.imageURL, imageData: $0.imageData, seen: $0.seen)
              },
              isYou: isYou)
    }
}

extension CachedPost {
    init(from p: Post) {
        id = p.id; author = p.author; meta = p.meta
        avatarGradient = p.avatarGradient.map(SessionColor.hex)
        avatarURL = p.avatarURL; imageURL = p.imageURL; imageData = p.imageData
        videoURL = p.videoURL
        imageAspect = Double(p.imageAspect); text = p.text
        showFollow = p.showFollow; liked = p.liked; bookmarked = p.bookmarked
        following = p.following; likeCount = p.likeCount; commentCount = p.commentCount
        isHalfWidth = p.isHalfWidth
    }

    func asDomain() -> Post {
        Post(id: id, author: author, meta: meta,
             avatarGradient: SessionColor.colors(from: avatarGradient),
             avatarURL: avatarURL, imageURL: imageURL, imageData: imageData,
             videoURL: videoURL,
             imageAspect: CGFloat(imageAspect), text: text,
             showFollow: showFollow, liked: liked, bookmarked: bookmarked,
             following: following, likeCount: likeCount, commentCount: commentCount,
             isHalfWidth: isHalfWidth)
    }
}

extension CachedVideo {
    init(from v: VideoItem) {
        id = v.id; title = v.title; channel = v.channel; meta = v.meta
        duration = v.duration; thumbGradient = v.thumbGradient.map(SessionColor.hex)
        thumbURL = v.thumbURL; thumbData = v.thumbData; videoURL = v.videoURL
        likes = v.likes; liked = v.liked; saved = v.saved
    }

    func asDomain() -> VideoItem {
        VideoItem(id: id, title: title, channel: channel, meta: meta,
                  duration: duration, thumbGradient: SessionColor.colors(from: thumbGradient),
                  thumbURL: thumbURL, thumbData: thumbData, videoURL: videoURL,
                  likes: likes, liked: liked, saved: saved)
    }
}

extension CachedShort {
    init(from s: Short) {
        id = s.id; channel = s.channel; subscribers = s.subscribers; caption = s.caption
        gradient = s.gradient.map(SessionColor.hex)
        imageURL = s.imageURL; imageData = s.imageData; videoURL = s.videoURL
        liked = s.liked; bookmarked = s.bookmarked; following = s.following; likeCount = s.likeCount
    }

    func asDomain() -> Short {
        Short(id: id, channel: channel, subscribers: subscribers, caption: caption,
              gradient: SessionColor.colors(from: gradient),
              imageURL: imageURL, imageData: imageData, videoURL: videoURL,
              liked: liked, bookmarked: bookmarked, following: following, likeCount: likeCount)
    }
}

extension CachedProduct {
    init(from p: Product) {
        id = p.id; name = p.name; price = p.price; meta = p.meta
        gradient = p.gradient.map(SessionColor.hex)
        imageURL = p.imageURL; saved = p.saved
        category = p.category; seller = p.seller
        condition = p.condition; distance = p.distance; description = p.description
    }

    func asDomain() -> Product {
        Product(id: id, name: name, price: price, meta: meta,
                gradient: SessionColor.colors(from: gradient),
                imageURL: imageURL, saved: saved,
                category: category ?? "All", seller: seller ?? "seller",
                condition: condition ?? "Good", distance: distance ?? "nearby",
                description: description ?? "")
    }
}

extension CachedPerson {
    init(from p: PersonSuggestion) {
        id = p.id; name = p.name
        gradient = p.gradient.map(SessionColor.hex)
        avatarURL = p.avatarURL; following = p.following
    }

    func asDomain() -> PersonSuggestion {
        PersonSuggestion(id: id, name: name,
                         gradient: SessionColor.colors(from: gradient),
                         avatarURL: avatarURL, following: following)
    }
}

extension CachedComment {
    init(from c: Comment) {
        id = c.id; author = c.author; text = c.text; avatarURL = c.avatarURL
        liked = c.liked; likeCount = c.likeCount; timeAgo = c.timeAgo
    }

    func asDomain() -> Comment {
        Comment(id: id, author: author, text: text, avatarURL: avatarURL,
                liked: liked, likeCount: likeCount, timeAgo: timeAgo)
    }
}

extension CachedChatMessage {
    init(from m: ChatMessage) {
        id = m.id; text = m.text; fromUser = m.fromUser
    }

    func asDomain() -> ChatMessage {
        ChatMessage(id: id, text: text, fromUser: fromUser)
    }
}
