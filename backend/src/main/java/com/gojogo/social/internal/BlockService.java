package com.gojogo.social.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Blocking, and the single place every other read asks about it.
 *
 * <p><b>One row, two directions.</b> Only the blocker gets a row — blocking is
 * something one person does to another, not a mutual state — but the visibility
 * rule is symmetric: neither party sees the other in a feed, a thread, a
 * profile, a search result or a video. A one-directional filter would leave the
 * blocked person still reading everything, which is the exact thing somebody
 * blocks to stop. Hence {@link BlockRepository#eitherWay}: there is deliberately
 * no query that answers only half of it.
 *
 * <p><b>Blocking unfollows, and it does so here.</b> Removing the two follow
 * rows in the same transaction as the block is what makes the feed correct
 * immediately rather than after a listener runs — and the feed being briefly
 * wrong is exactly the failure a safety feature cannot have. It is also why the
 * table lives in {@code social} beside {@code follow} rather than in
 * {@code profile}: half a graph in each module makes this two transactions.
 *
 * <p><b>The block is not announced.</b> No event, no notification, nothing on
 * the other person's screen changes visibly — a product that tells someone they
 * were blocked hands them a reason to open a second account.
 */
@Service
class BlockService {

    /** Matches the row seeded by V28; read at the call site, not cached. */
    private static final long DEFAULT_MAX_BLOCKS = 5000;

    /**
     * The id nobody has. JPQL cannot render {@code not in ()}, so an exclusion
     * list that might be empty is padded with a value that excludes nothing —
     * one line here instead of a second copy of every query for the
     * overwhelmingly common case of a person who has blocked no one.
     */
    static final UUID NOBODY = new UUID(0L, 0L);

    static Set<UUID> orNobody(Set<UUID> ids) {
        if (ids.isEmpty()) {
            return Set.of(NOBODY);
        }
        Set<UUID> padded = new java.util.HashSet<>(ids);
        padded.add(NOBODY);
        return padded;
    }

    private final BlockRepository blocks;
    private final FollowRepository follows;
    private final CloseFriendRepository closeFriends;
    private final StoryMuteRepository mutes;
    private final ProfileApi profiles;
    private final ConfigApi config;

    BlockService(BlockRepository blocks, FollowRepository follows,
                 CloseFriendRepository closeFriends, StoryMuteRepository mutes,
                 ProfileApi profiles, ConfigApi config) {
        this.blocks = blocks;
        this.follows = follows;
        this.closeFriends = closeFriends;
        this.mutes = mutes;
        this.profiles = profiles;
        this.config = config;
    }

    @Transactional
    void block(UUID me, UUID otherId) {
        if (me.equals(otherId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Cannot block yourself");
        }
        ProfileDto other = profiles.findById(otherId).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "No such profile"));
        // A business profile is blockable — it publishes, so it can be a
        // nuisance — but blocking one must not be a way to reach its owner:
        // these are separate identities and the block applies to the one named.
        if (blocks.existsById(new Block.Key(me, otherId))) {
            return; // idempotent: tapping Block on an already-blocked account is a no-op
        }
        long limit = config.number("social.max.blocks", DEFAULT_MAX_BLOCKS);
        if (blocks.countByBlockerId(me) >= limit) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "You have blocked the maximum of " + limit + " accounts");
        }
        try {
            blocks.saveAndFlush(new Block(me, otherId));
        } catch (DataIntegrityViolationException raced) {
            return; // two taps, one block
        }
        // Everything the two of them had pointing at each other, severed in the
        // same transaction as the block itself.
        follows.deleteByFollowerIdAndFolloweeId(me, otherId);
        follows.deleteByFollowerIdAndFolloweeId(otherId, me);
        closeFriends.severBetween(me, otherId);
        // A mute is now redundant and would silently outlive an unblock,
        // leaving someone quietly hidden with no UI that says so.
        mutes.deleteByMuterIdAndMutedId(me, other.id());
        mutes.deleteByMuterIdAndMutedId(other.id(), me);
    }

    /**
     * Unblocking restores visibility and nothing else. The follows a block
     * removed are not put back: re-following is a decision, and quietly
     * resurrecting a relationship somebody ended is the wrong default.
     */
    @Transactional
    void unblock(UUID me, UUID otherId) {
        blocks.deleteByBlockerIdAndBlockedId(me, otherId);
    }

    /** The settings list: only the accounts <em>I</em> blocked, newest first —
     *  who blocked me is deliberately not knowable from here. */
    @Transactional(readOnly = true)
    List<BlockedProfileDto> mine(UUID me) {
        List<Block> rows = blocks.findByBlockerIdOrderByCreatedAtDesc(me);
        if (rows.isEmpty()) {
            return List.of();
        }
        Map<UUID, ProfileDto> named = profiles.findByIds(
            rows.stream().map(Block::getBlockedId).collect(Collectors.toSet()));
        return rows.stream().map(row -> {
            ProfileDto p = named.get(row.getBlockedId());
            return new BlockedProfileDto(
                row.getBlockedId(),
                p == null ? "Deleted user" : p.displayName() != null ? p.displayName() : p.handle(),
                p == null ? null : p.handle(),
                p == null ? null : p.avatarUrl(),
                row.getCreatedAt());
        }).toList();
    }

    /**
     * Everyone this person cannot see and cannot be seen by — both directions,
     * unioned here and nowhere else. This is the only way out of the two
     * one-directional repository queries, on purpose: a caller with access to
     * just "who I blocked" would write the filter that leaves the blocked person
     * reading everything.
     */
    @Transactional(readOnly = true)
    Set<UUID> hiddenFrom(UUID me) {
        if (me == null) {
            return Set.of();
        }
        Set<UUID> hidden = new java.util.HashSet<>(blocks.blockedBy(me));
        hidden.addAll(blocks.blockersOf(me));
        return hidden;
    }

    @Transactional(readOnly = true)
    boolean between(UUID a, UUID b) {
        return a != null && b != null && !a.equals(b) && blocks.countBetween(a, b) > 0;
    }

    /** Whether I am the one holding the block — the only half a client is told
     *  about, because it is the only half it can undo. */
    @Transactional(readOnly = true)
    boolean iBlocked(UUID me, UUID otherId) {
        return blocks.existsById(new Block.Key(me, otherId));
    }
}
