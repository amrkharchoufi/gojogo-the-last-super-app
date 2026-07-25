package com.gojogo.social;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Domain event published when someone replies to a story frame. Consumed by the
 * notifications module to tell the frame's author — who is the only person that
 * can read the reply.
 */
public record StoryReplied(UUID frameId, UUID storyAuthorId, UUID replierId,
                           UUID commentId, OffsetDateTime at) {
}
