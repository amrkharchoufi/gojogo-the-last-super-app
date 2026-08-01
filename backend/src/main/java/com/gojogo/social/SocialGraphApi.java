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

    /**
     * Everyone this user must not see, <em>and</em> must not be seen by.
     *
     * <p>A block is recorded one-directionally and enforced symmetrically, and
     * this set is already both halves — a caller filters a page of content
     * against it and is done. There is no API that returns only "who I blocked",
     * because a consumer that used it would leave the blocked person reading
     * everything, which is the whole thing blocking exists to stop.
     *
     * <p>Read it once per request and filter in memory; it is small (a person
     * blocks tens of accounts, not thousands) and one query beats a check per
     * row.
     */
    Set<UUID> blockedIds(UUID userId);

    /** The same question about one specific pair, for a caller that has two ids
     *  rather than a page of content. Order does not matter. */
    boolean blockedBetween(UUID a, UUID b);
}
