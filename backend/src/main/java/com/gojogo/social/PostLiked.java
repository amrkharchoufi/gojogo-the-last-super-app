package com.gojogo.social;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Domain event published when a post is liked. Consumed by the notifications
 * module to tell the post's author. Not published on unlike (no notification to
 * retract for now).
 */
public record PostLiked(UUID postId, UUID postAuthorId, UUID likerId, OffsetDateTime at) {
}
