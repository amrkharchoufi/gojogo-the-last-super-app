package com.gojogo.social;

import java.util.UUID;

/**
 * Domain event published on a new follow. No consumers yet (see PostCreated).
 */
public record UserFollowed(UUID followerId, UUID followeeId) {
}
