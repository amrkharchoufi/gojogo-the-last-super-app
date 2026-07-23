package com.gojogo.social;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Domain event published when a comment is added to a post. Consumed by the
 * notifications module to tell the post's author.
 */
public record PostCommented(UUID postId, UUID postAuthorId, UUID commenterId,
                            UUID commentId, OffsetDateTime at) {
}
