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
    private(set) var remoteFrameIds: Set<UUID> = []
    private(set) var remoteCommentIds: Set<UUID> = []
    private(set) var authorIdByPost: [UUID: UUID] = [:]
    private(set) var profileIdByHandle: [String: UUID] = [:]

    var myProfileId: UUID?
    var myHandle: String = ""

    func reset() {
        remotePostIds = []
        remoteFrameIds = []
        remoteCommentIds = []
        authorIdByPost = [:]
        profileIdByHandle = [:]
        myProfileId = nil
        myHandle = ""
    }

    func profileId(forHandle handle: String) -> UUID? {
        profileIdByHandle[handle.lowercased()]
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
            mediaItems: slides.map { CreateMediaItemBody(imageUrl: $0.imageUrl, videoUrl: $0.videoUrl) })
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

    func addComment(_ text: String, to postId: UUID) async throws -> Comment {
        let dto: CommentDTO = try await APIClient.shared
            .post("/v1/posts/\(postId.uuidString.lowercased())/comments", body: CreateCommentBody(text: text))
        return map(dto)
    }

    func likeComment(_ commentId: UUID) async throws {
        try await APIClient.shared.post("/v1/comments/\(commentId.uuidString.lowercased())/like")
    }

    func unlikeComment(_ commentId: UUID) async throws {
        try await APIClient.shared.delete("/v1/comments/\(commentId.uuidString.lowercased())/like")
    }

    // MARK: Stories

    func fetchStories() async throws -> [Story] {
        let rings: [StoryRingDTO] = try await APIClient.shared.get("/v1/stories")
        return rings.map { map($0) }
    }

    @discardableResult
    func createStory(frameUrls: [String]) async throws -> [StoryFrameDTO] {
        let frames: [StoryFrameDTO] = try await APIClient.shared
            .post("/v1/stories", body: CreateStoryBody(frameImageUrls: frameUrls))
        for frame in frames {
            remoteFrameIds.insert(frame.id)
        }
        return frames
    }

    func markFrameSeen(_ frameId: UUID) async throws {
        try await APIClient.shared.post("/v1/stories/frames/\(frameId.uuidString.lowercased())/seen")
    }

    // MARK: Mapping

    func map(_ dto: PostDTO) -> Post {
        register(dto.author)
        remotePostIds.insert(dto.id)
        authorIdByPost[dto.id] = dto.author.id
        let slides = dto.mediaItems.map {
            PostMediaItem(id: $0.id, imageURL: $0.imageUrl, videoURL: $0.videoUrl)
        }
        let handle = dto.author.handle ?? "user"
        let isOwn = dto.author.id == myProfileId
        return Post(
            id: dto.id,
            author: handle,
            meta: BackendDate.relative(dto.createdAt),
            avatarGradient: Self.gradient(for: handle),
            avatarURL: dto.author.avatarUrl,
            imageURL: slides.first(where: { !$0.isVideo })?.imageURL,
            videoURL: slides.first(where: \.isVideo)?.videoURL,
            mediaItems: slides,
            imageAspect: CGFloat(dto.imageAspect),
            text: dto.text,
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
        return Comment(
            id: dto.id,
            author: dto.author.handle ?? dto.author.name ?? "user",
            text: dto.text,
            avatarURL: dto.author.avatarUrl,
            liked: dto.liked,
            likeCount: dto.likeCount,
            timeAgo: BackendDate.relative(dto.createdAt))
    }

    func map(_ ring: StoryRingDTO) -> Story {
        if let handle = ring.handle {
            profileIdByHandle[handle.lowercased()] = ring.authorId
        }
        for frame in ring.frames {
            remoteFrameIds.insert(frame.id)
        }
        let display = ring.isYou ? "You" : (ring.handle ?? ring.name)
        return Story(
            id: ring.authorId,
            name: display,
            letter: String((ring.name.first ?? "g").uppercased()),
            gradient: Self.gradient(for: ring.handle ?? ring.name),
            frames: ring.frames.map {
                StoryFrame(id: $0.id, imageURL: $0.imageUrl, seen: $0.seen)
            },
            isYou: ring.isYou)
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
