package com.gojogo.notifications.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.data.domain.Limit;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Persists activity rows (from the event listeners) and serves the feed,
 * decorated with the actor's profile. Self-actions (liking your own post,
 * commenting on your own post) never create a notification.
 */
@Service
class NotificationService {

    private final NotificationRepository repo;
    private final DeviceTokenRepository deviceTokens;
    private final ProfileApi profiles;
    private final ApnsPushSender apns;

    NotificationService(NotificationRepository repo, DeviceTokenRepository deviceTokens,
                        ProfileApi profiles, ApnsPushSender apns) {
        this.repo = repo;
        this.deviceTokens = deviceTokens;
        this.profiles = profiles;
        this.apns = apns;
    }

    @Transactional
    void record(UUID recipientId, String type, UUID actorId,
                UUID postId, UUID commentId, OffsetDateTime at) {
        if (recipientId == null || recipientId.equals(actorId)) return;
        repo.save(new Notification(recipientId, type, actorId, postId, commentId, at));
        // Best-effort APNs push (no-op unless a push key is configured).
        apns.notify(recipientId, actorId, type, postId);
    }

    @Transactional
    void registerDevice(UUID userId, String token, String platform) {
        deviceTokens.findByToken(token).ifPresentOrElse(
            existing -> { existing.reassign(userId); deviceTokens.save(existing); },
            () -> deviceTokens.save(new DeviceToken(userId, token,
                platform == null ? "ios" : platform)));
    }

    void unregisterDevice(String token) {
        deviceTokens.deleteByToken(token);
    }

    @Transactional(readOnly = true)
    NotificationsPage list(UUID userId, OffsetDateTime before, int limit) {
        int capped = Math.min(Math.max(limit, 1), 50);
        List<Notification> rows = before == null
            ? repo.findByRecipientIdOrderByCreatedAtDesc(userId, Limit.of(capped))
            : repo.findByRecipientIdAndCreatedAtBeforeOrderByCreatedAtDesc(userId, before, Limit.of(capped));

        Map<UUID, ProfileDto> actors = profiles.findByIds(rows.stream().map(Notification::getActorId).toList());
        List<NotificationDto> items = rows.stream().map(n -> toDto(n, actors)).toList();
        OffsetDateTime nextBefore = rows.size() == capped && !rows.isEmpty()
            ? rows.get(rows.size() - 1).getCreatedAt() : null;
        return new NotificationsPage(items, nextBefore);
    }

    @Transactional(readOnly = true)
    long unreadCount(UUID userId) {
        return repo.countByRecipientIdAndReadFalse(userId);
    }

    @Transactional
    void markAllRead(UUID userId) {
        repo.markAllRead(userId);
    }

    private NotificationDto toDto(Notification n, Map<UUID, ProfileDto> actors) {
        ProfileDto p = actors.get(n.getActorId());
        String name = p != null ? (p.displayName() != null ? p.displayName() : p.handle()) : "Someone";
        ActorDto actor = new ActorDto(n.getActorId(), name,
            p != null ? p.handle() : null, p != null ? p.avatarUrl() : null);
        return new NotificationDto(n.getId(), n.getType(), actor,
            n.getPostId(), n.getCommentId(), textFor(n.getType()), n.getCreatedAt(), n.isRead());
    }

    private static String textFor(String type) {
        return switch (type) {
            case "follow" -> "started following you";
            case "like" -> "liked your post";
            case "comment" -> "commented on your post";
            default -> "";
        };
    }
}
