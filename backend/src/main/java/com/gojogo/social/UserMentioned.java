package com.gojogo.social;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Domain event published when someone is tagged in a post caption or a comment.
 * Consumed by the notifications module to tell the person who was tagged.
 *
 * <p>{@code commentId} is null for a caption tag — the pair (postId, commentId)
 * is what lets the activity feed open the right thing on tap.
 */
public record UserMentioned(UUID mentionedProfileId, UUID actorId,
                            UUID postId, UUID commentId, OffsetDateTime at) {
}
