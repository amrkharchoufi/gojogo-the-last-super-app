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
    // Business profiles (Phase 2e M1). All optional so a build either side of a
    // backend roll still decodes the view.
    var kind: String?          // "PERSON" | "BUSINESS"
    var verified: Bool?
    /// The viewer owns this business — what turns a business page into "yours".
    var isOwner: Bool?
    var business: BusinessBlockDTO?
}

/// The business-only half of a profile view; nil for a person.
struct BusinessBlockDTO: Decodable {
    var ownerProfileId: UUID?
    var contactPhone: String?
    var contactEmail: String?
    var websiteUrl: String?
    var addressLine: String?
    var city: String?
    var country: String?
    var latitude: Double?
    var longitude: Double?
    var openingHours: String?
}

// MARK: - Business profiles (owner side)

/// One business the caller runs — the profile half and the business half in one
/// payload, because to everyone outside the profile module they are one identity.
struct BusinessProfileDTO: Decodable, Identifiable {
    var id: UUID
    var handle: String
    var displayName: String?
    var bio: String?
    var category: String?
    var avatarUrl: String?
    var ownerProfileId: UUID?
    var verified: Bool
    var contactPhone: String?
    var contactEmail: String?
    var websiteUrl: String?
    var addressLine: String?
    var city: String?
    var country: String?
    var latitude: Double?
    var longitude: Double?
    var openingHours: String?
}

struct CreateBusinessBody: Encodable {
    var displayName: String
    var handle: String?
    var category: String?
    var bio: String?
    var avatarUrl: String?
    var contactPhone: String?
    var contactEmail: String?
    var websiteUrl: String?
    var addressLine: String?
    var city: String?
    var country: String?
    var latitude: Double?
    var longitude: Double?
    var openingHours: String?
}

/// PATCH semantics: a nil field means unchanged, not cleared.
struct UpdateBusinessBody: Encodable {
    var displayName: String?
    var handle: String?
    var category: String?
    var bio: String?
    var avatarUrl: String?
    var contactPhone: String?
    var contactEmail: String?
    var websiteUrl: String?
    var addressLine: String?
    var city: String?
    var country: String?
    var latitude: Double?
    var longitude: Double?
    var openingHours: String?
}

/// `GET /v1/me/roles` — what this account can be right now. Roles are derived
/// server-side (owning a business, an approved application), never stored.
struct MyRolesDTO: Decodable {
    var profileId: UUID
    var hasBusiness: Bool
    var businesses: [BusinessRoleDTO]
    var partners: [PartnerRoleDTO]
    var merchantIds: [UUID]?
    var isDriver: Bool?
    var isCourier: Bool?
}

struct BusinessRoleDTO: Decodable {
    var profileId: UUID
    var handle: String
    var displayName: String?
    var avatarUrl: String?
    var category: String?
    var verified: Bool
}

struct PartnerRoleDTO: Decodable {
    var kind: String
    var status: String
    var refId: UUID?
    var businessProfileId: UUID?
}

struct AuthorSummaryDTO: Decodable {
    var id: UUID
    var name: String?
    var handle: String?
    var avatarUrl: String?
    var following: Bool
    /// Business profiles (Phase 2e M1) — optional so an older backend decodes.
    var business: Bool?
    var verified: Bool?
}

struct MediaItemDTO: Decodable {
    var id: UUID
    var imageUrl: String?
    var videoUrl: String?
}

/// Someone tagged in a caption or a comment. `handle` is the handle *as written*
/// — the token to find in the body text — while `profileId` is what a tap
/// follows, and it survives that person renaming themselves.
struct MentionDTO: Decodable {
    var profileId: UUID
    var handle: String
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
    /// Optional so a build either side of the tagging deploy still decodes the
    /// feed rather than dropping it.
    var mentions: [MentionDTO]?
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
    /// Post as a business profile you own; nil posts as yourself. Verified
    /// server-side against ownership — never a client-side trust.
    var actAsProfileId: String?
}

/// Threads are one level deep: a top-level comment carries its `replies`, and a
/// reply's own `replies` is always empty. Everything past `createdAt` is
/// optional so a build predating the threading deploy still decodes.
struct CommentDTO: Decodable {
    var id: UUID
    var author: AuthorSummaryDTO
    var text: String
    var liked: Bool
    var likeCount: Int
    var createdAt: String
    var parentId: UUID?
    var replyCount: Int?
    var mentions: [MentionDTO]?
    var replies: [CommentDTO]?
}

struct CreateCommentBody: Encodable {
    var text: String
    /// The comment being answered; nil posts a new top-level comment. A reply to
    /// a reply is re-pointed at their shared parent server-side.
    var parentId: String?
    var actAsProfileId: String?
}

/// One row of the people picker behind the @-tag autocomplete.
struct ProfileSearchResultDTO: Decodable {
    var id: UUID
    var name: String?
    var handle: String?
    var avatarUrl: String?
    var business: Bool?
    var verified: Bool?
}

// MARK: - Watch (long-form + shorts)

/// The channel behind a video. `subscriberCount` is the author's real follower
/// count — subscribers *are* followers, resolved server-side.
struct VideoChannelDTO: Decodable {
    var id: UUID
    var name: String?
    var handle: String?
    var avatarUrl: String?
    var subscriberCount: Int
    var subscribed: Bool
    var business: Bool?
    var verified: Bool?
}

/// Optional past `id` for the same reason story frames are: an app build either
/// side of a backend roll must still decode the item rather than drop the feed.
struct VideoDTO: Decodable {
    var id: UUID
    var kind: String?
    var channel: VideoChannelDTO
    var title: String?
    var description: String?
    var thumbUrl: String?
    var videoUrl: String?
    var durationSeconds: Int?
    var liked: Bool
    var saved: Bool
    var likeCount: Int
    var commentCount: Int
    var viewCount: Int
    var createdAt: String?
}

struct VideoFeedDTO: Decodable {
    var videos: [VideoDTO]
    var nextBefore: String?
}

struct CreateVideoBody: Encodable {
    var kind: String
    var title: String?
    var description: String?
    var thumbUrl: String?
    var videoUrl: String
    var durationSeconds: Int?
    var actAsProfileId: String?
}

/// A nil field means "leave it alone" server-side, not "clear it".
struct UpdateVideoBody: Encodable {
    var title: String?
    var description: String?
    var thumbUrl: String?
}

struct VideoCommentDTO: Decodable {
    var id: UUID
    var author: VideoChannelDTO
    var text: String
    var liked: Bool
    var likeCount: Int
    var createdAt: String?
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
    var actAsProfileId: String?
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
    var actAsProfileId: String?
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
