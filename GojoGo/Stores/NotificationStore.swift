import Foundation

/// Notifications-module API surface (activity feed) + DTO→ActivityItem mapping.
/// Server UUIDs are reused as the ActivityItem ids.
@MainActor
final class NotificationStore {

    static let shared = NotificationStore()

    func fetch(before: String? = nil, limit: Int = 30) async throws
        -> (items: [ActivityItem], nextBefore: String?) {
        var path = "/v1/notifications?limit=\(limit)"
        if let before,
           let encoded = before.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&before=\(encoded)"
        }
        let page: NotificationsPageDTO = try await APIClient.shared.get(path)
        return (page.items.map { map($0) }, page.nextBefore)
    }

    func unreadCount() async throws -> Int {
        let dto: UnreadCountDTO = try await APIClient.shared.get("/v1/notifications/unread-count")
        return dto.count
    }

    func markAllRead() async throws {
        try await APIClient.shared.post("/v1/notifications/read")
    }

    func registerDevice(_ token: String) async throws {
        try await APIClient.shared.postNoContent(
            "/v1/push/register", body: RegisterPushBody(token: token, platform: "ios"))
    }

    /// Drops this device from push fan-out — how "turn notifications off" is honoured.
    func unregisterDevice(_ token: String) async throws {
        try await APIClient.shared.postNoContent(
            "/v1/push/unregister", body: UnregisterPushBody(token: token))
    }

    func map(_ dto: NotificationDTO) -> ActivityItem {
        // Registering the actor keeps a tapped row's profile openable by id
        // rather than by whatever name it happens to render under.
        if let handle = dto.actor.handle {
            SocialStore.shared.registerProfile(id: dto.actor.id, handle: handle)
        }
        return ActivityItem(
            id: dto.id,
            kind: ActivityKind(rawValue: dto.type) ?? .system,
            actor: dto.actor.name ?? dto.actor.handle ?? "Someone",
            actorHandle: dto.actor.handle,
            actorID: dto.actor.id,
            actorFollowed: dto.actorFollowed ?? false,
            text: dto.text,
            snippet: dto.snippet,
            timeAgo: BackendDate.relative(dto.createdAt),
            createdAt: BackendDate.parse(dto.createdAt) ?? Date(),
            read: dto.read,
            avatarURL: dto.actor.avatarUrl,
            previewURL: dto.previewUrl,
            postID: dto.postId,
            commentID: dto.commentId,
            storyFrameID: dto.storyFrameId)
    }
}
