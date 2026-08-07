package com.gojogo.notifications.internal;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/** Wire DTOs for the activity feed. */
final class Dtos {
    private Dtos() {}
}

record ActorDto(UUID id, String name, String handle, String avatarUrl) {
}

/**
 * One activity row, decorated with everything the feed needs to render it
 * without a second round trip.
 *
 * <p>{@code previewUrl} and {@code snippet} are what answer "which post?" —
 * the thumbnail of the thing this is about, and the words that identify it
 * (the comment, when there is one; otherwise the post's own caption). Either
 * can be null: a text-only post has no thumbnail, a picture with no caption has
 * no snippet.
 *
 * <p>{@code actorFollowed} is the recipient's side of the follow graph, which
 * is what lets a "started following you" row carry a Follow-back button instead
 * of making the user open a profile to find out.
 */
record NotificationDto(
    UUID id,
    String type,
    ActorDto actor,
    UUID postId,
    UUID commentId,
    UUID storyFrameId,
    String text,
    String previewUrl,
    String snippet,
    boolean actorFollowed,
    OffsetDateTime createdAt,
    boolean read) {
}

record NotificationsPage(List<NotificationDto> items, OffsetDateTime nextBefore) {
}

record UnreadCountDto(long count) {
}
