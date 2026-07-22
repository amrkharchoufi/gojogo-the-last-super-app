package com.gojogo.social;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Domain event published when a post is created. No consumers yet — the
 * publish side exists so search/activity can subscribe later at zero cost
 * to this module (ARCHITECTURE.md §7, Milestone 2).
 */
public record PostCreated(UUID postId, UUID authorId, OffsetDateTime createdAt) {
}
