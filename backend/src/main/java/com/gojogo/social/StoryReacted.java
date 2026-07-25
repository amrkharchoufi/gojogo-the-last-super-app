package com.gojogo.social;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Domain event published when a viewer reacts to a story frame. Consumed by the
 * notifications module to tell the frame's author. Not published when the
 * reaction is removed (nothing to retract), nor when it merely changes emoji.
 */
public record StoryReacted(UUID frameId, UUID storyAuthorId, UUID reactorId,
                           String emoji, OffsetDateTime at) {
}
