package com.gojogo.share;

import java.time.Duration;
import java.util.List;
import java.util.UUID;

/**
 * Minting and revoking public links. Four verbs, and none of them knows what a
 * ride is.
 */
public interface ShareApi {

    /**
     * A link to one thing, or the live one that already exists for this
     * {@code (kind, refId, owner, reason)}.
     *
     * <p><strong>Idempotent on purpose.</strong> Tapping Share twice should
     * produce the same link, not scatter two secrets for the same trip — the
     * second one would be un-revokable by anybody who had already sent the
     * first. A link whose remaining life is shorter than the one asked for is
     * extended rather than replaced, so re-sharing a trip that is running late
     * keeps working for the person already watching it.
     *
     * @param ttl how long from now it should live. The caller knows what it is
     *            sharing; this module only knows how to count
     */
    SharedLink mint(String kind, UUID refId, UUID ownerId, ShareReason reason, Duration ttl);

    /**
     * Kills a link. Used when the thing it points at ends early, and by the
     * person who made it.
     *
     * <p>Revoking is the only way back: a link that has been sent cannot be
     * un-sent, so this is what "stop sharing" actually means.
     */
    void revoke(String kind, UUID refId, UUID ownerId);

    /** Every live link this person minted for one thing — what a "you're sharing
     *  this trip" banner is drawn from. */
    List<SharedLink> liveLinksFor(String kind, UUID refId, UUID ownerId);

    /** Why a link exists. A share is the owner's choice and theirs to revoke;
     *  an SOS is an alarm and is deliberately not revocable by a tap. */
    enum ShareReason {
        SHARE,
        SOS
    }

    /**
     * @param url the address to actually send somebody. Built from the
     *            configured base so a universal-link domain can change without
     *            every caller learning about it
     */
    record SharedLink(UUID id, String token, String url, String kind, UUID refId,
                      ShareReason reason, java.time.OffsetDateTime expiresAt,
                      int viewCount) {
    }
}
