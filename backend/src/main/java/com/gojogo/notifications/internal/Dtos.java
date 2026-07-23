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

record NotificationDto(
    UUID id,
    String type,
    ActorDto actor,
    UUID postId,
    UUID commentId,
    String text,
    OffsetDateTime createdAt,
    boolean read) {
}

record NotificationsPage(List<NotificationDto> items, OffsetDateTime nextBefore) {
}

record UnreadCountDto(long count) {
}
