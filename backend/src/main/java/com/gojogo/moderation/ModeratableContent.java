package com.gojogo.moderation;

import java.util.Optional;
import java.util.UUID;

/**
 * How one vertical's content is looked at, and taken down, by the moderation
 * queue — implemented <em>by</em> that vertical and called by this module.
 *
 * <p>The direction is the point (see the package docs). Moderation cannot know
 * what a post, a short or a listing is without depending on every vertical in
 * the platform, which would invert the layering and make the module unextractable.
 * So each vertical registers a handler for the kinds it owns, and moderation
 * holds nothing but a pointer.
 *
 * <p>An implementation is trusted to be honest about two things and nothing
 * else: <b>who owns the content</b>, which is what a suspension decision reads,
 * and <b>a one-line summary</b>, which is what a moderator sees before deciding.
 * The summary must be the content's own words or title, truncated — never an
 * interpretation, and never a link the operator's browser has to follow.
 */
public interface ModeratableContent {

    /** The kind this handler answers for. Exactly one handler per kind. */
    ModerationTargetKind kind();

    /**
     * What is at this id, or empty if there is nothing there.
     *
     * <p>Empty is not an error: content gets deleted by its own author between a
     * report being filed and a moderator opening it, and the queue should say
     * "already gone" rather than break.
     */
    Optional<ModerationTarget> look(UUID targetId);

    /**
     * Applies a decision.
     *
     * <p>Only {@link ModerationAction#HIDE}, {@link ModerationAction#REMOVE} and
     * {@link ModerationAction#RESTORE} reach here — {@code SUSPEND} is about an
     * account and is handled by this module itself. A handler that cannot
     * support one of them (a profile cannot be "hidden") throws
     * {@link UnsupportedOperationException} and the caller turns it into a 409
     * naming the combination, rather than reporting a success that did nothing.
     */
    void apply(UUID targetId, ModerationAction action);

    /**
     * One reported thing, as the queue renders it.
     *
     * @param ownerId  whose it is — copied onto the report so the queue still
     *                 names somebody after the content is removed
     * @param summary  the content's own first words or title, truncated
     * @param hidden   whether a moderator has already hidden it, so the queue
     *                 can offer Restore instead of Hide
     */
    record ModerationTarget(UUID ownerId, String summary, boolean hidden) {
    }
}
