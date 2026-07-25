import Foundation

// Typed mirrors of the backend DTOs (dates stay as ISO-8601 strings; parse via `BackendDate`).

struct SessionDTO: Decodable {
    var profileId: UUID
    var cognitoSub: String
    var email: String?
    var displayName: String?
    var handle: String?
}

// Native Apple sign-in exchange (POST /v1/auth/apple).
struct AppleAuthBody: Encodable {
    var identityToken: String
    var rawNonce: String
    var fullName: String?
}

struct AppleTokenDTO: Decodable {
    var idToken: String
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Int
}

struct ProfileDTO: Decodable {
    var id: UUID
    var cognitoSub: String
    var email: String?
    var displayName: String?
    var handle: String
    var bio: String
    var category: String
    var birthYear: Int?
    var avatarUrl: String?
    var interests: [String]
}

struct UpdateProfileBody: Encodable {
    var displayName: String?
    var handle: String?
    var bio: String?
    var category: String?
    var birthYear: Int?
    var avatarUrl: String?
    var interests: [String]?
}

// MARK: - Username (handle) change

struct ChangeHandleBody: Encodable {
    var handle: String
}

struct HandleAvailabilityDTO: Decodable {
    var available: Bool
    var reason: String   // "ok" | "taken" | "invalid" | "current"
    var normalized: String
}

struct HandleStatusDTO: Decodable {
    var handle: String
    var handleChangedAt: String?
    var changeAvailableAt: String?  // nil => can change now
    var canChangeNow: Bool
}

struct ProfileViewDTO: Decodable {
    var id: UUID
    var name: String
    var handle: String
    var avatarUrl: String?
    var bio: String
    var category: String
    var postCount: Int
    var followerCount: Int
    var followingCount: Int
    var isOwn: Bool
    var following: Bool
}

struct AuthorSummaryDTO: Decodable {
    var id: UUID
    var name: String?
    var handle: String?
    var avatarUrl: String?
    var following: Bool
}

struct MediaItemDTO: Decodable {
    var id: UUID
    var imageUrl: String?
    var videoUrl: String?
}

struct PostDTO: Decodable {
    var id: UUID
    var author: AuthorSummaryDTO
    var createdAt: String
    var text: String?
    var imageAspect: Double
    var mediaItems: [MediaItemDTO]
    var liked: Bool
    var bookmarked: Bool
    var likeCount: Int
    var commentCount: Int
}

struct FeedDTO: Decodable {
    var posts: [PostDTO]
    var nextBefore: String?
}

struct CreateMediaItemBody: Encodable {
    var imageUrl: String?
    var videoUrl: String?
}

struct CreatePostBody: Encodable {
    var text: String?
    var imageAspect: Double?
    var mediaItems: [CreateMediaItemBody]
}

struct CommentDTO: Decodable {
    var id: UUID
    var author: AuthorSummaryDTO
    var text: String
    var liked: Bool
    var likeCount: Int
    var createdAt: String
}

struct CreateCommentBody: Encodable {
    var text: String
}

/// Every field past `id` is optional so a build of the app that predates a
/// backend roll (or vice versa) still decodes the frame instead of dropping the
/// whole rail.
struct StoryFrameDTO: Decodable {
    var id: UUID
    var mediaType: String?
    var imageUrl: String?
    var videoUrl: String?
    var durationMs: Int?
    var caption: String?
    var overlays: String?
    var background: String?
    var audience: String?
    var seen: Bool
    var createdAt: String?
    var expiresAt: String?
    var viewerCount: Int?
    var replyCount: Int?
    var myReaction: String?
    var music: StoryMusicDTO?
}

struct StoryMusicDTO: Decodable {
    var trackId: UUID
    var title: String
    var artist: String?
    var artworkUrl: String?
    var audioUrl: String
    var startMs: Int
    var durationMs: Int
}

struct MusicTrackDTO: Decodable {
    var id: UUID
    var title: String
    var artist: String?
    var artworkUrl: String?
    var audioUrl: String
    var durationMs: Int
}

struct StoryRingDTO: Decodable {
    var authorId: UUID
    var name: String
    var handle: String?
    var avatarUrl: String?
    var isYou: Bool
    var muted: Bool?
    var frames: [StoryFrameDTO]
}

struct CreateStoryFrameBody: Encodable {
    var mediaType: String
    var imageUrl: String?
    var videoUrl: String?
    var durationMs: Int?
    var caption: String?
    var overlays: String?
    var background: String?
    var audience: String?
    /// Only the id and the window — the server resolves everything displayed,
    /// so a client can't post a frame claiming to be a song it isn't.
    var musicTrackId: UUID?
    var musicStartMs: Int?
    var musicDurationMs: Int?
}

struct CreateStoryBody: Encodable {
    var frames: [CreateStoryFrameBody]
}

struct StoryReactionBody: Encodable {
    var emoji: String
}

struct StoryReplyBody: Encodable {
    var text: String
}

struct StoryReplyDTO: Decodable {
    var id: UUID
    var frameId: UUID
    var authorId: UUID
    var authorName: String?
    var authorHandle: String?
    var authorAvatarUrl: String?
    var text: String
    var createdAt: String?
    var mine: Bool
}

struct StoryViewerDTO: Decodable {
    var id: UUID
    var name: String?
    var handle: String?
    var avatarUrl: String?
    var reaction: String?
    var viewedAt: String?
}

struct StoryHighlightDTO: Decodable {
    var id: UUID
    var ownerId: UUID
    var title: String
    var coverUrl: String?
    var frameCount: Int
}

struct StoryHighlightDetailDTO: Decodable {
    var id: UUID
    var ownerId: UUID
    var title: String
    var coverUrl: String?
    var frames: [StoryFrameDTO]
}

struct SaveHighlightBody: Encodable {
    var title: String
    var coverUrl: String?
    var frameIds: [UUID]
}

struct CloseFriendsBody: Encodable {
    var profileIds: [UUID]
}

struct CloseFriendDTO: Decodable {
    var id: UUID
    var name: String?
    var handle: String?
    var avatarUrl: String?
}

struct PresignBody: Encodable {
    var contentType: String
}

struct PresignDTO: Decodable {
    var uploadUrl: String
    var key: String
    var publicUrl: String
    var contentType: String
    var expiresSeconds: Int
    // Signed Cache-Control the backend stamped on the presigned PUT — must be
    // replayed verbatim on the upload or S3 rejects the signature. Optional so
    // older backends (no field) still decode.
    var cacheControl: String?
}

// MARK: - Notifications (activity feed)

struct NotificationActorDTO: Decodable {
    var id: UUID
    var name: String?
    var handle: String?
    var avatarUrl: String?
}

struct NotificationDTO: Decodable {
    var id: UUID
    var type: String
    var actor: NotificationActorDTO
    var postId: UUID?
    var commentId: UUID?
    var text: String
    var createdAt: String
    var read: Bool
}

struct NotificationsPageDTO: Decodable {
    var items: [NotificationDTO]
    var nextBefore: String?
}

struct UnreadCountDTO: Decodable {
    var count: Int
}

struct RegisterPushBody: Encodable {
    var token: String
    var platform: String
}

struct UnregisterPushBody: Encodable {
    var token: String
}

// MARK: - Backend timestamps

enum BackendDate {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Backend sends nanosecond fractions; trim to milliseconds before parsing.
    static func parse(_ raw: String) -> Date? {
        let trimmed = raw.replacingOccurrences(
            of: #"(\.\d{1,3})\d*"#, with: "$1", options: .regularExpression)
        return iso.date(from: trimmed) ?? isoPlain.date(from: raw)
    }

    static func relative(_ raw: String) -> String {
        guard let date = parse(raw) else { return "now" }
        let seconds = max(0, Date().timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        case ..<604_800: return "\(Int(seconds / 86_400))d"
        default: return "\(Int(seconds / 604_800))w"
        }
    }
}
