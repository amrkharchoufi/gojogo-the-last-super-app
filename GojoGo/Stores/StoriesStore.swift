import SwiftUI

/// Stories API surface (rings, composing, engagement, highlights) plus DTO→UI
/// mapping. Server UUIDs are reused as the UI model ids so every mutation can
/// address the backend directly — the same contract `SocialStore` uses.
///
/// Split out of `SocialStore` when stories stopped being "a list of image
/// URLs": rings, replies, viewers, mutes, the archive, highlights and close
/// friends are their own surface, and they were about to double that file.
@MainActor
final class StoriesStore {

    static let shared = StoriesStore()

    /// Frames that exist on the server — mutations on anything else stay local
    /// (SampleData rings, or a frame whose upload is still in flight).
    private(set) var remoteFrameIds: Set<UUID> = []

    /// Authors whose stories this user muted, mirrored from the rings response
    /// so the rail can render the state without a second call.
    private(set) var mutedAuthorIds: Set<UUID> = []

    func reset() {
        remoteFrameIds = []
        mutedAuthorIds = []
    }

    func isLive(_ frameID: UUID) -> Bool { remoteFrameIds.contains(frameID) }

    // MARK: Rings

    func fetchRings() async throws -> [Story] {
        let rings: [StoryRingDTO] = try await APIClient.shared.get("/v1/stories")
        mutedAuthorIds = Set(rings.filter { $0.muted == true }.map(\.authorId))
        return rings.map { map($0) }
    }

    @discardableResult
    func create(_ frames: [CreateStoryFrameBody]) async throws -> [StoryFrameDTO] {
        let created: [StoryFrameDTO] = try await APIClient.shared
            .post("/v1/stories", body: CreateStoryBody(frames: frames))
        for frame in created {
            remoteFrameIds.insert(frame.id)
        }
        return created
    }

    func markSeen(_ frameID: UUID) async throws {
        try await APIClient.shared.post("/v1/stories/frames/\(path(frameID))/seen")
    }

    func delete(_ frameID: UUID) async throws {
        try await APIClient.shared.delete("/v1/stories/frames/\(path(frameID))")
        remoteFrameIds.remove(frameID)
    }

    // MARK: Reactions + replies

    func react(_ frameID: UUID, emoji: String) async throws {
        try await APIClient.shared.putNoContent("/v1/stories/frames/\(path(frameID))/reaction",
                                                body: StoryReactionBody(emoji: emoji))
    }

    func unreact(_ frameID: UUID) async throws {
        try await APIClient.shared.delete("/v1/stories/frames/\(path(frameID))/reaction")
    }

    func replies(_ frameID: UUID) async throws -> [StoryReply] {
        let list: [StoryReplyDTO] = try await APIClient.shared
            .get("/v1/stories/frames/\(path(frameID))/replies")
        return list.map { map($0) }
    }

    @discardableResult
    func reply(_ frameID: UUID, text: String) async throws -> StoryReply {
        let dto: StoryReplyDTO = try await APIClient.shared
            .post("/v1/stories/frames/\(path(frameID))/replies", body: StoryReplyBody(text: text))
        return map(dto)
    }

    func deleteReply(_ replyID: UUID) async throws {
        try await APIClient.shared.delete("/v1/stories/replies/\(path(replyID))")
    }

    func viewers(_ frameID: UUID) async throws -> [StoryViewerInfo] {
        let list: [StoryViewerDTO] = try await APIClient.shared
            .get("/v1/stories/frames/\(path(frameID))/viewers")
        return list.map {
            StoryViewerInfo(
                id: $0.id,
                name: $0.handle ?? $0.name ?? "Someone",
                handle: $0.handle,
                avatarURL: $0.avatarUrl,
                reaction: $0.reaction,
                timeAgo: BackendDate.relative($0.viewedAt ?? ""))
        }
    }

    // MARK: Mute

    func mute(_ profileID: UUID) async throws {
        try await APIClient.shared.post("/v1/stories/mute/\(path(profileID))")
        mutedAuthorIds.insert(profileID)
    }

    func unmute(_ profileID: UUID) async throws {
        try await APIClient.shared.delete("/v1/stories/mute/\(path(profileID))")
        mutedAuthorIds.remove(profileID)
    }

    // MARK: Archive + highlights

    func archive() async throws -> [StoryFrame] {
        let list: [StoryFrameDTO] = try await APIClient.shared.get("/v1/stories/archive")
        for frame in list { remoteFrameIds.insert(frame.id) }
        return list.map { map($0) }
    }

    func highlights(of profileID: UUID? = nil) async throws -> [StoryHighlight] {
        var path = "/v1/stories/highlights"
        if let profileID {
            path += "?profileId=\(profileID.uuidString.lowercased())"
        }
        let list: [StoryHighlightDTO] = try await APIClient.shared.get(path)
        return list.map {
            StoryHighlight(id: $0.id, ownerID: $0.ownerId, title: $0.title,
                           coverURL: $0.coverUrl, frameCount: $0.frameCount)
        }
    }

    /// A highlight opened for playback — returns the ring the viewer plays.
    func highlightFrames(_ highlightID: UUID) async throws -> (title: String, frames: [StoryFrame]) {
        let dto: StoryHighlightDetailDTO = try await APIClient.shared
            .get("/v1/stories/highlights/\(path(highlightID))")
        for frame in dto.frames { remoteFrameIds.insert(frame.id) }
        return (dto.title, dto.frames.map { map($0) })
    }

    @discardableResult
    func saveHighlight(id: UUID?, title: String, coverURL: String?,
                       frameIDs: [UUID]) async throws -> StoryHighlight {
        let body = SaveHighlightBody(title: title, coverUrl: coverURL, frameIds: frameIDs)
        let dto: StoryHighlightDTO = id == nil
            ? try await APIClient.shared.post("/v1/stories/highlights", body: body)
            : try await APIClient.shared.put("/v1/stories/highlights/\(path(id!))", body: body)
        return StoryHighlight(id: dto.id, ownerID: dto.ownerId, title: dto.title,
                              coverURL: dto.coverUrl, frameCount: dto.frameCount)
    }

    func deleteHighlight(_ highlightID: UUID) async throws {
        try await APIClient.shared.delete("/v1/stories/highlights/\(path(highlightID))")
    }

    // MARK: Close friends

    func closeFriends() async throws -> [CloseFriend] {
        let list: [CloseFriendDTO] = try await APIClient.shared.get("/v1/stories/close-friends")
        return list.map { map($0) }
    }

    @discardableResult
    func setCloseFriends(_ ids: [UUID]) async throws -> [CloseFriend] {
        let list: [CloseFriendDTO] = try await APIClient.shared
            .put("/v1/stories/close-friends", body: CloseFriendsBody(profileIds: ids))
        return list.map { map($0) }
    }

    // MARK: Mapping

    func map(_ ring: StoryRingDTO) -> Story {
        if let handle = ring.handle {
            SocialStore.shared.registerProfile(id: ring.authorId, handle: handle)
        }
        for frame in ring.frames {
            remoteFrameIds.insert(frame.id)
        }
        return Story(
            id: ring.authorId,
            name: ring.isYou ? "You" : (ring.handle ?? ring.name),
            letter: String((ring.name.first ?? "g").uppercased()),
            gradient: SocialStore.gradient(for: ring.handle ?? ring.name),
            frames: ring.frames.map { map($0) },
            isYou: ring.isYou,
            avatarURL: ring.avatarUrl,
            muted: ring.muted ?? false)
    }

    func map(_ dto: StoryFrameDTO) -> StoryFrame {
        StoryFrame(
            id: dto.id,
            kind: StoryMediaKind(wire: dto.mediaType),
            imageURL: dto.imageUrl,
            videoURL: dto.videoUrl,
            durationMs: dto.durationMs,
            caption: dto.caption,
            background: StoryBackground.named(dto.background),
            overlays: [StoryOverlay].fromStoryJSON(dto.overlays),
            audience: StoryAudience(wire: dto.audience),
            music: dto.music.map { map($0) },
            seen: dto.seen,
            viewerCount: dto.viewerCount,
            replyCount: dto.replyCount,
            myReaction: dto.myReaction,
            createdAt: dto.createdAt.flatMap { BackendDate.parse($0) },
            expiresAt: dto.expiresAt.flatMap { BackendDate.parse($0) })
    }

    private func map(_ dto: StoryMusicDTO) -> StoryMusic {
        StoryMusic(
            trackID: dto.trackId,
            title: dto.title,
            artist: dto.artist ?? "Unknown artist",
            artworkURL: dto.artworkUrl,
            audioURL: dto.audioUrl,
            startMs: dto.startMs,
            durationMs: dto.durationMs)
    }

    private func map(_ dto: StoryReplyDTO) -> StoryReply {
        StoryReply(
            id: dto.id,
            frameID: dto.frameId,
            authorID: dto.authorId,
            authorName: dto.authorHandle ?? dto.authorName ?? "Someone",
            authorHandle: dto.authorHandle,
            authorAvatarURL: dto.authorAvatarUrl,
            text: dto.text,
            timeAgo: BackendDate.relative(dto.createdAt ?? ""),
            mine: dto.mine)
    }

    private func map(_ dto: CloseFriendDTO) -> CloseFriend {
        CloseFriend(id: dto.id, name: dto.handle ?? dto.name ?? "Someone",
                    handle: dto.handle, avatarURL: dto.avatarUrl)
    }

    private func path(_ id: UUID) -> String { id.uuidString.lowercased() }
}
