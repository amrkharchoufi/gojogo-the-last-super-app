import SwiftUI

/// Social-module API surface (feed, posts, stories, comments, follows) plus
/// DTO→UI-model mapping. Server UUIDs are reused as the UI model ids so
/// mutations (like, comment, seen) can address the backend directly.
@MainActor
final class SocialStore {

    static let shared = SocialStore()

    /// Server-backed content ids — AppState uses these to decide whether a
    /// mutation should hit the API or stay local (sample content).
    private(set) var remotePostIds: Set<UUID> = []
    private(set) var remoteCommentIds: Set<UUID> = []
    private(set) var authorIdByPost: [UUID: UUID] = [:]
    private(set) var profileIdByHandle: [String: UUID] = [:]

    var myProfileId: UUID?
    var myHandle: String = ""
    /// The business profiles this account owns (Phase 2e M1). Kept in sync by
    /// `AppState.refreshBusinessProfiles`; content authored by one of these is
    /// this user's own, whichever identity they're switched to.
    var ownedBusinessIds: Set<UUID> = []

    func reset() {
        remotePostIds = []
        remoteCommentIds = []
        authorIdByPost = [:]
        profileIdByHandle = [:]
        myProfileId = nil
        myHandle = ""
        ownedBusinessIds = []
    }

    func profileId(forHandle handle: String) -> UUID? {
        profileIdByHandle[handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()]
    }

    /// The current handle for an id this device has seen. The reverse direction
    /// matters for tags: the id in a tag outlives the handle written next to it.
    func handle(forProfileId id: UUID) -> String? {
        profileIdByHandle.first { $0.value == id }?.key
    }

    func registerProfile(id: UUID, handle: String) {
        profileIdByHandle[handle.lowercased()] = id
    }

    // MARK: Feed / posts

    func fetchFeed(before: String? = nil, limit: Int = 30) async throws
        -> (posts: [Post], nextBefore: String?) {
        var path = "/v1/feed?limit=\(limit)"
        if let before,
           let encoded = before.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&before=\(encoded)"
        }
        let feed: FeedDTO = try await APIClient.shared.get(path)
        return (feed.posts.map { map($0) }, feed.nextBefore)
    }

    func createPost(text: String?, slides: [(imageUrl: String?, videoUrl: String?)],
                    imageAspect: Double) async throws -> Post {
        let body = CreatePostBody(
            text: text,
            imageAspect: imageAspect,
            mediaItems: slides.map { CreateMediaItemBody(imageUrl: $0.imageUrl, videoUrl: $0.videoUrl) },
            actAsProfileId: ActingIdentity.shared.actAsProfileId)
        let dto: PostDTO = try await APIClient.shared.post("/v1/posts", body: body)
        return map(dto)
    }

    func like(_ postId: UUID) async throws {
        try await APIClient.shared.post("/v1/posts/\(postId.uuidString.lowercased())/like")
    }

    func unlike(_ postId: UUID) async throws {
        try await APIClient.shared.delete("/v1/posts/\(postId.uuidString.lowercased())/like")
    }

    func bookmark(_ postId: UUID) async throws {
        try await APIClient.shared.post("/v1/posts/\(postId.uuidString.lowercased())/bookmark")
    }

    func unbookmark(_ postId: UUID) async throws {
        try await APIClient.shared.delete("/v1/posts/\(postId.uuidString.lowercased())/bookmark")
    }

    func deletePost(_ postId: UUID) async throws {
        try await APIClient.shared.delete("/v1/posts/\(postId.uuidString.lowercased())")
    }

    // MARK: Follows

    func follow(_ profileId: UUID) async throws {
        try await APIClient.shared.post("/v1/profiles/\(profileId.uuidString.lowercased())/follow")
    }

    func unfollow(_ profileId: UUID) async throws {
        try await APIClient.shared.delete("/v1/profiles/\(profileId.uuidString.lowercased())/follow")
    }

    // MARK: Comments

    func comments(for postId: UUID) async throws -> [Comment] {
        let list: [CommentDTO] = try await APIClient.shared
            .get("/v1/posts/\(postId.uuidString.lowercased())/comments")
        return list.map { map($0) }
    }

    /// `parentID` posts a reply instead of a new top-level comment. A reply to a
    /// reply is re-pointed at their shared parent server-side, so the caller can
    /// pass whichever comment the user actually tapped.
    func addComment(_ text: String, to postId: UUID, parentID: UUID? = nil) async throws -> Comment {
        let dto: CommentDTO = try await APIClient.shared
            .post("/v1/posts/\(postId.uuidString.lowercased())/comments",
                  body: CreateCommentBody(text: text,
                                          parentId: parentID?.uuidString.lowercased(),
                                          actAsProfileId: ActingIdentity.shared.actAsProfileId))
        return map(dto)
    }

    func replies(for commentId: UUID) async throws -> [Comment] {
        let list: [CommentDTO] = try await APIClient.shared
            .get("/v1/comments/\(commentId.uuidString.lowercased())/replies")
        return list.map { map($0) }
    }

    // MARK: People picker (@-tag autocomplete)

    func searchProfiles(_ query: String, limit: Int = 8) async throws -> [MentionCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return [] }
        let list: [ProfileSearchResultDTO] = try await APIClient.shared
            .get("/v1/profiles/search?q=\(encoded)&limit=\(limit)")
        return list.compactMap { dto in
            guard let handle = dto.handle else { return nil }
            registerProfile(id: dto.id, handle: handle)
            return MentionCandidate(id: dto.id, name: dto.name ?? handle, handle: handle,
                                    avatarURL: dto.avatarUrl,
                                    verified: dto.verified ?? false,
                                    business: dto.business ?? false)
        }
    }

    func likeComment(_ commentId: UUID) async throws {
        try await APIClient.shared.post("/v1/comments/\(commentId.uuidString.lowercased())/like")
    }

    func unlikeComment(_ commentId: UUID) async throws {
        try await APIClient.shared.delete("/v1/comments/\(commentId.uuidString.lowercased())/like")
    }

    // MARK: Mapping

    func map(_ dto: PostDTO) -> Post {
        register(dto.author)
        remotePostIds.insert(dto.id)
        authorIdByPost[dto.id] = dto.author.id
        let items = dto.mediaItems.map {
            PostMediaItem(id: $0.id, imageURL: $0.imageUrl, videoURL: $0.videoUrl)
        }
        // A voice post's m4a arrives in the file slot a video would use. Pulling
        // it out here is what keeps it from being played as a video, counted as
        // a carousel slide, or drawn as a black tile in the photo grid.
        let audioURL = items.first(where: { AudioLibrary.isAudioRef($0.videoURL) })?.videoURL
        let slides = items.filter { !AudioLibrary.isAudioRef($0.videoURL) }
        let handle = dto.author.handle ?? "user"
        // Yours, or one of your business profiles' — a Follow chip on your own
        // shop's post is the tell that the app forgot which identities are you.
        let isOwn = dto.author.id == myProfileId || ownedBusinessIds.contains(dto.author.id)
        return Post(
            id: dto.id,
            author: handle,
            meta: BackendDate.relative(dto.createdAt),
            avatarGradient: Self.gradient(for: handle),
            avatarURL: dto.author.avatarUrl,
            imageURL: slides.first(where: { !$0.isVideo })?.imageURL,
            videoURL: slides.first(where: \.isVideo)?.videoURL,
            audioURL: audioURL,
            mediaItems: slides,
            imageAspect: CGFloat(dto.imageAspect),
            text: dto.text,
            mentions: map(dto.mentions),
            showFollow: !dto.author.following && !isOwn,
            liked: dto.liked,
            bookmarked: dto.bookmarked,
            following: dto.author.following,
            likeCount: dto.likeCount,
            commentCount: dto.commentCount)
    }

    func map(_ dto: CommentDTO) -> Comment {
        register(dto.author)
        remoteCommentIds.insert(dto.id)
        let replies = (dto.replies ?? []).map { map($0) }
        return Comment(
            id: dto.id,
            author: dto.author.handle ?? dto.author.name ?? "user",
            text: dto.text,
            avatarURL: dto.author.avatarUrl,
            liked: dto.liked,
            likeCount: dto.likeCount,
            timeAgo: BackendDate.relative(dto.createdAt),
            parentID: dto.parentId,
            // Trust the server's count when it sends one, but never let it read
            // as fewer replies than are actually in hand.
            replyCount: max(dto.replyCount ?? 0, replies.count),
            mentions: map(dto.mentions),
            replies: replies)
    }

    /// Also seeds the handle→id table: a tag is often the first time this device
    /// has heard of that account, and the profile screen opens by handle.
    private func map(_ dtos: [MentionDTO]?) -> [Mention] {
        (dtos ?? []).map {
            registerProfile(id: $0.profileId, handle: $0.handle)
            return Mention(profileID: $0.profileId, handle: $0.handle)
        }
    }

    private func register(_ author: AuthorSummaryDTO) {
        if let handle = author.handle {
            profileIdByHandle[handle.lowercased()] = author.id
        }
    }

    /// Stable avatar gradient per handle (no server-side avatar colors).
    static func gradient(for handle: String) -> [Color] {
        let palette: [[String]] = [
            ["26E0A8", "0E7B5E"], ["5AC8FA", "2C5F8A"], ["FF9F5A", "B34A18"],
            ["C792EA", "6A3E9E"], ["F76D8A", "9E2A46"], ["FFD166", "B07C1E"],
            ["4DD0B1", "1E6B5C"], ["7EA6F7", "2C4A9E"],
        ]
        let index = abs(handle.lowercased().hashValue) % palette.count
        return palette[index].map { Color(hex: $0) }
    }
}
