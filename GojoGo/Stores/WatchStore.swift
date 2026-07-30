import SwiftUI

/// Watch API surface (long-form feed, Shorts, engagement, comments) plus
/// DTO→UI-model mapping. Server UUIDs are reused as the UI model ids so every
/// mutation can address the backend directly — the same contract `SocialStore`
/// and `StoriesStore` use.
@MainActor
final class WatchStore {

    static let shared = WatchStore()

    /// Videos and shorts that exist on the server. A mutation on anything else
    /// (a clip whose upload is still in flight, or one restored from the local
    /// session cache after a sign-out) stays local.
    private(set) var remoteVideoIds: Set<UUID> = []
    private(set) var remoteCommentIds: Set<UUID> = []
    /// Author profile id per video — lets a Subscribe tap address the follow
    /// endpoint without a handle lookup.
    private(set) var channelIdByVideo: [UUID: UUID] = [:]
    /// Real follower counts seen on any video's channel, keyed by lowercased
    /// handle. `AppState` merges these so the "N subscribers" line is right for
    /// a channel whose profile was never opened.
    private(set) var subscriberCountByHandle: [String: Int] = [:]

    func reset() {
        remoteVideoIds = []
        remoteCommentIds = []
        channelIdByVideo = [:]
        subscriberCountByHandle = [:]
    }

    func isLive(_ id: UUID) -> Bool { remoteVideoIds.contains(id) }

    func channelId(forVideo id: UUID) -> UUID? { channelIdByVideo[id] }

    // MARK: Feeds

    /// The long-form Watch feed.
    func fetchVideos(before: String? = nil, limit: Int = 20) async throws
        -> (videos: [VideoItem], nextBefore: String?) {
        let page: VideoFeedDTO = try await APIClient.shared.get(feedPath(kind: "LONG_FORM",
                                                                        limit: limit, before: before))
        return (page.videos.map { mapVideo($0) }, page.nextBefore)
    }

    /// The vertical Shorts pager.
    func fetchShorts(before: String? = nil, limit: Int = 20) async throws
        -> (shorts: [Short], nextBefore: String?) {
        let page: VideoFeedDTO = try await APIClient.shared.get(feedPath(kind: "SHORT",
                                                                        limit: limit, before: before))
        return (page.videos.map { mapShort($0) }, page.nextBefore)
    }

    private func feedPath(kind: String, limit: Int, before: String?) -> String {
        var path = "/v1/videos?kind=\(kind)&limit=\(limit)"
        if let before,
           let encoded = before.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&before=\(encoded)"
        }
        return path
    }

    /// A channel's uploads — the profile reels grid.
    func fetchChannelVideos(_ profileID: UUID) async throws -> [VideoDTO] {
        let list: [VideoDTO] = try await APIClient.shared
            .get("/v1/profiles/\(path(profileID))/videos?limit=60")
        for dto in list { register(dto) }
        return list
    }

    // MARK: Publishing

    func create(kind: String, title: String?, description: String?,
                thumbUrl: String?, videoUrl: String, durationSeconds: Int?) async throws -> VideoDTO {
        let body = CreateVideoBody(kind: kind, title: title, description: description,
                                   thumbUrl: thumbUrl, videoUrl: videoUrl,
                                   durationSeconds: durationSeconds,
                                   actAsProfileId: ActingIdentity.shared.actAsProfileId)
        let dto: VideoDTO = try await APIClient.shared.post("/v1/videos", body: body)
        register(dto)
        return dto
    }

    @discardableResult
    func update(_ id: UUID, title: String?, description: String?, thumbUrl: String?) async throws -> VideoDTO {
        let dto: VideoDTO = try await APIClient.shared.patch(
            "/v1/videos/\(path(id))",
            body: UpdateVideoBody(title: title, description: description, thumbUrl: thumbUrl))
        register(dto)
        return dto
    }

    func delete(_ id: UUID) async throws {
        try await APIClient.shared.delete("/v1/videos/\(path(id))")
        remoteVideoIds.remove(id)
        channelIdByVideo[id] = nil
    }

    // MARK: Engagement

    func like(_ id: UUID) async throws {
        try await APIClient.shared.post("/v1/videos/\(path(id))/like")
    }

    func unlike(_ id: UUID) async throws {
        try await APIClient.shared.delete("/v1/videos/\(path(id))/like")
    }

    func save(_ id: UUID) async throws {
        try await APIClient.shared.post("/v1/videos/\(path(id))/save")
    }

    func unsave(_ id: UUID) async throws {
        try await APIClient.shared.delete("/v1/videos/\(path(id))/save")
    }

    /// Idempotent per viewer server-side, so this is safe to fire on any open.
    func recordView(_ id: UUID) async throws {
        try await APIClient.shared.post("/v1/videos/\(path(id))/view")
    }

    // MARK: Comments

    func comments(for videoID: UUID) async throws -> [Comment] {
        let list: [VideoCommentDTO] = try await APIClient.shared
            .get("/v1/videos/\(path(videoID))/comments")
        return list.map { mapComment($0) }
    }

    func addComment(_ text: String, to videoID: UUID) async throws -> Comment {
        let dto: VideoCommentDTO = try await APIClient.shared
            .post("/v1/videos/\(path(videoID))/comments",
                  body: CreateCommentBody(text: text,
                                          actAsProfileId: ActingIdentity.shared.actAsProfileId))
        return mapComment(dto)
    }

    func likeComment(_ commentID: UUID) async throws {
        try await APIClient.shared.post("/v1/video-comments/\(path(commentID))/like")
    }

    func unlikeComment(_ commentID: UUID) async throws {
        try await APIClient.shared.delete("/v1/video-comments/\(path(commentID))/like")
    }

    // MARK: Mapping

    func mapVideo(_ dto: VideoDTO) -> VideoItem {
        register(dto)
        let handle = dto.channel.handle ?? dto.channel.name ?? "user"
        return VideoItem(
            id: dto.id,
            title: dto.title ?? "Untitled video",
            channel: handle,
            details: dto.description ?? "",
            duration: Self.durationLabel(dto.durationSeconds ?? 0),
            thumbGradient: SocialStore.gradient(for: handle),
            thumbURL: dto.thumbUrl,
            videoURL: dto.videoUrl,
            authorAvatarURL: dto.channel.avatarUrl,
            likes: dto.likeCount,
            liked: dto.liked,
            saved: dto.saved,
            views: dto.viewCount,
            commentCount: dto.commentCount,
            publishedAt: dto.createdAt.flatMap { BackendDate.parse($0) } ?? Date())
    }

    func mapShort(_ dto: VideoDTO) -> Short {
        register(dto)
        let handle = dto.channel.handle ?? dto.channel.name ?? "user"
        return Short(
            id: dto.id,
            channel: handle,
            // A short has no separate body — its caption rides in `title`, and
            // the server's "Untitled short" placeholder reads as no caption.
            caption: (dto.title == "Untitled short" ? "" : dto.title) ?? "",
            gradient: SocialStore.gradient(for: handle),
            imageURL: dto.thumbUrl,
            videoURL: dto.videoUrl,
            authorAvatarURL: dto.channel.avatarUrl,
            liked: dto.liked,
            bookmarked: dto.saved,
            following: dto.channel.subscribed,
            likeCount: dto.likeCount,
            views: dto.viewCount,
            publishedAt: dto.createdAt.flatMap { BackendDate.parse($0) } ?? Date())
    }

    private func mapComment(_ dto: VideoCommentDTO) -> Comment {
        remoteCommentIds.insert(dto.id)
        if let handle = dto.author.handle {
            SocialStore.shared.registerProfile(id: dto.author.id, handle: handle)
        }
        return Comment(
            id: dto.id,
            author: dto.author.handle ?? dto.author.name ?? "user",
            text: dto.text,
            avatarURL: dto.author.avatarUrl,
            liked: dto.liked,
            likeCount: dto.likeCount,
            timeAgo: BackendDate.relative(dto.createdAt ?? ""))
    }

    private func register(_ dto: VideoDTO) {
        remoteVideoIds.insert(dto.id)
        channelIdByVideo[dto.id] = dto.channel.id
        if let handle = dto.channel.handle {
            SocialStore.shared.registerProfile(id: dto.channel.id, handle: handle)
            subscriberCountByHandle[handle.lowercased()] = dto.channel.subscriberCount
        }
    }

    /// "1:00" / "1:02:03" from whole seconds — the server stores the number,
    /// the client owns the formatting.
    static func durationLabel(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func path(_ id: UUID) -> String { id.uuidString.lowercased() }
}
