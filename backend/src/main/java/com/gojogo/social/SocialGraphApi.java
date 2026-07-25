package com.gojogo.social;

import java.util.Collection;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Read-only view of the follow graph for other modules.
 *
 * <p>The graph lives in {@code social} because that is where following is
 * created, but it is not a social-only fact: Watch ranks a feed by who you
 * follow and shows a channel's follower count as its subscriber count — one
 * relationship, one number, no second graph.
 *
 * <p>Deliberately read-only. Following is created through the social REST
 * surface so the {@link UserFollowed} event and its notification stay in one
 * place; a module that needs to <em>change</em> the graph should send the user
 * there rather than get a write method here.
 */
public interface SocialGraphApi {

    /** Who this user follows. Never includes the user themselves. */
    Set<UUID> followeeIds(UUID userId);

    /**
     * Follower counts for a batch of profiles — this is what a "subscribers"
     * line renders. Ids with no followers are present with a count of 0, so a
     * caller can tell "nobody yet" apart from "unknown".
     */
    Map<UUID, Long> followerCounts(Collection<UUID> profileIds);
}
