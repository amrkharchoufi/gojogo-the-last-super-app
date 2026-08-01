package com.gojogo.moderation;

/**
 * What a moderator decided to do. Four verbs, and the ordering of them matters:
 * the first is reversible, the second is not, the third is about a person rather
 * than a thing, and the fourth undoes the first.
 */
public enum ModerationAction {

    /**
     * Out of everyone else's reads; still visible, flagged, to its author. The
     * default, and the one a moderator working a queue at speed should reach for
     * — being wrong about a hide costs an appeal, being wrong about a removal
     * costs somebody's work.
     */
    HIDE,

    /** Gone. For content that must not survive the mistake of keeping it. */
    REMOVE,

    /**
     * The account, not the content: sign-in is disabled and every session
     * revoked. Nothing is deleted — a suspension is meant to be liftable, and
     * the evidence has to outlive the decision.
     */
    SUSPEND,

    /** Undoes a {@link #HIDE}, and lifts a {@link #SUSPEND}. */
    RESTORE;

    public static ModerationAction parse(String raw) {
        if (raw != null) {
            for (ModerationAction action : values()) {
                if (action.name().equalsIgnoreCase(raw.trim())) {
                    return action;
                }
            }
        }
        throw new IllegalArgumentException("Unknown action: " + raw);
    }
}
