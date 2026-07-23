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

struct StoryFrameDTO: Decodable {
    var id: UUID
    var imageUrl: String
    var seen: Bool
    var createdAt: String
}

struct StoryRingDTO: Decodable {
    var authorId: UUID
    var name: String
    var handle: String?
    var avatarUrl: String?
    var isYou: Bool
    var frames: [StoryFrameDTO]
}

struct CreateStoryBody: Encodable {
    var frameImageUrls: [String]
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
