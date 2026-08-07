package com.gojogo.notifications.internal;

import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import com.gojogo.social.ContentPreview;
import com.gojogo.social.SocialContentApi;
import com.gojogo.social.SocialGraphApi;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Limit;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;

/**
 * Persists activity rows (from the event listeners) and serves the feed,
 * decorated with the actor's profile. Self-actions (liking your own post,
 * commenting on your own post) never create a notification.
 */
@Service
class NotificationService {

    private static final Logger log = LoggerFactory.getLogger(NotificationService.class);

    private final NotificationRepository repo;
    private final DeviceTokenRepository deviceTokens;
    private final ProfileApi profiles;
    private final SocialContentApi content;
    private final SocialGraphApi graph;
    private final ApnsPushSender apns;

    NotificationService(NotificationRepository repo, DeviceTokenRepository deviceTokens,
                        ProfileApi profiles, SocialContentApi content, SocialGraphApi graph,
                        ApnsPushSender apns) {
        this.repo = repo;
        this.deviceTokens = deviceTokens;
        this.profiles = profiles;
        this.content = content;
        this.graph = graph;
        this.apns = apns;
    }

    @Transactional
    void record(UUID recipientId, String type, UUID actorId,
                UUID postId, UUID commentId, OffsetDateTime at) {
        record(recipientId, type, actorId, postId, commentId, null, at);
    }

    @Transactional
    void record(UUID recipientId, String type, UUID actorId,
                UUID postId, UUID commentId, UUID storyFrameId, OffsetDateTime at) {
        if (recipientId == null || recipientId.equals(actorId)) return;
        repo.save(new Notification(recipientId, type, actorId, postId, commentId, storyFrameId, at));
        // Best-effort APNs push (no-op unless a push key is configured).
        apns.notify(recipientId, actorId, type, postId, commentId, storyFrameId);
    }

    /**
     * Points a device at the account that just signed in on it.
     *
     * <p><b>Reassignment is deliberate.</b> APNs issues one token per device per
     * app, not per person, so a phone that is handed over — logged out, logged
     * back in as somebody else — presents the same token under a new account.
     * Refusing to move it would leave the new owner with no notifications at
     * all, so this is the behaviour rather than a hole.
     *
     * <p>It is still worth a line in the log. Taking a device over requires
     * already knowing its token, which nothing in this system ever discloses —
     * but if one did leak, this is where it would be spent, and a hand-off that
     * nobody can see afterwards is one that cannot be investigated. Logged at
     * INFO with no token in the message: the identifier is the credential, and
     * writing it here would put it in exactly the log a leak would come from.
     */
    @Transactional
    void registerDevice(UUID userId, String token, String platform) {
        deviceTokens.findByToken(token).ifPresentOrElse(
            existing -> {
                UUID previous = existing.getProfileId();
                if (previous != null && !previous.equals(userId)) {
                    log.info("Device handed over: push token moves from profile {} to {}",
                        previous, userId);
                }
                existing.reassign(userId);
                deviceTokens.save(existing);
            },
            () -> deviceTokens.save(new DeviceToken(userId, token,
                platform == null ? "ios" : platform)));
    }

    /** Scoped to the caller: a device token is deleted only from the account
     *  that presents it, so knowing someone else's token cannot silently
     *  disable their push (including safety notifications). */
    @Transactional
    void unregisterDevice(UUID userId, String token) {
        deviceTokens.deleteByProfileIdAndToken(userId, token);
    }

    @Transactional(readOnly = true)
    NotificationsPage list(UUID userId, OffsetDateTime before, int limit) {
        int capped = Math.min(Math.max(limit, 1), 50);
        List<Notification> rows = before == null
            ? repo.findByRecipientIdOrderByCreatedAtDesc(userId, Limit.of(capped))
            : repo.findByRecipientIdAndCreatedAtBeforeOrderByCreatedAtDesc(userId, before, Limit.of(capped));

        Map<UUID, ProfileDto> actors = profiles.findByIds(rows.stream().map(Notification::getActorId).toList());
        // One batch per kind of target for the whole page — see SocialContentApi.
        Map<UUID, ContentPreview> postPreviews = content.postPreviews(
            ids(rows, Notification::getPostId));
        Map<UUID, ContentPreview> storyPreviews = content.storyFramePreviews(
            ids(rows, Notification::getStoryFrameId));
        Map<UUID, ContentPreview> commentPreviews = content.commentPreviews(
            ids(rows, Notification::getCommentId));
        Set<UUID> followed = graph.followeeIds(userId);

        List<NotificationDto> items = rows.stream()
            .map(n -> toDto(n, actors, postPreviews, storyPreviews, commentPreviews, followed))
            .toList();
        OffsetDateTime nextBefore = rows.size() == capped && !rows.isEmpty()
            ? rows.get(rows.size() - 1).getCreatedAt() : null;
        return new NotificationsPage(items, nextBefore);
    }

    private static List<UUID> ids(List<Notification> rows,
                                  java.util.function.Function<Notification, UUID> field) {
        return rows.stream().map(field).filter(Objects::nonNull).distinct().toList();
    }

    @Transactional(readOnly = true)
    long unreadCount(UUID userId) {
        return repo.countByRecipientIdAndReadFalse(userId);
    }

    @Transactional
    void markAllRead(UUID userId) {
        repo.markAllRead(userId);
    }

    private NotificationDto toDto(Notification n, Map<UUID, ProfileDto> actors,
                                  Map<UUID, ContentPreview> postPreviews,
                                  Map<UUID, ContentPreview> storyPreviews,
                                  Map<UUID, ContentPreview> commentPreviews,
                                  Set<UUID> followed) {
        ProfileDto p = actors.get(n.getActorId());
        String name = p != null ? (p.displayName() != null ? p.displayName() : p.handle()) : "Someone";
        ActorDto actor = new ActorDto(n.getActorId(), name,
            p != null ? p.handle() : null, p != null ? p.avatarUrl() : null);

        // The picture is always the post's or the story's: a comment has none,
        // and a row about a comment is still a row about the post it is on.
        // Both ids are null on a follow, and an immutable empty map — which is
        // what an all-follows page gets back — throws rather than misses.
        ContentPreview target = n.getStoryFrameId() != null
            ? storyPreviews.get(n.getStoryFrameId())
            : (n.getPostId() == null ? null : postPreviews.get(n.getPostId()));
        // The words, though, come from the comment when there is one — "which
        // post" is answered by the thumbnail, and quoting the caption back at
        // its own author instead of what somebody just said is the less useful
        // half of the row.
        ContentPreview words = n.getCommentId() != null
            ? commentPreviews.get(n.getCommentId())
            : target;

        return new NotificationDto(n.getId(), n.getType(), actor,
            n.getPostId(), n.getCommentId(), n.getStoryFrameId(),
            textFor(n.getType(), n.getCommentId() != null),
            target == null ? null : target.thumbnailUrl(),
            words == null ? null : words.text(),
            followed.contains(n.getActorId()),
            n.getCreatedAt(), n.isRead());
    }

    /**
     * The phrase the row reads as.
     *
     * <p>A tag says where it happened. "Mentioned you" on its own leaves the
     * person guessing whether to look in a caption or in a thread, and the two
     * open different screens on tap — so the row that routes there says which.
     */
    private static String textFor(String type, boolean onComment) {
        return switch (type) {
            case "follow" -> "started following you";
            case "like" -> "liked your post";
            case "comment" -> "commented on your post";
            case "reply" -> "replied to your comment";
            case "mention" -> onComment ? "mentioned you in a comment" : "mentioned you in a post";
            case "story_reaction" -> "reacted to your story";
            case "story_reply" -> "replied to your story";
            default -> "";
        };
    }
}
