package com.gojogo.moderation;

/**
 * The kinds of thing that can be reported.
 *
 * <p>The set is closed and every member has a live {@link ModeratableContent}
 * behind it, because a report a moderator cannot act on is a queue item nobody
 * can ever close. SPECS §10 also lists {@code MESSAGE}, {@code ORDER} and
 * {@code RIDE}; those are deliberately absent until there is a surface that can
 * show a moderator the thing being complained about — a private DM in DynamoDB
 * is not something this queue can render, and rides do not exist until Phase 3.
 * Adding one later is a new enum constant plus a new handler bean, and no
 * migration: the column is a varchar for exactly that reason.
 */
public enum ModerationTargetKind {

    POST,
    COMMENT,
    STORY,
    VIDEO,
    /** The account itself, for behaviour no single piece of content captures. */
    PROFILE,
    LISTING;

    public static ModerationTargetKind parse(String raw) {
        if (raw != null) {
            for (ModerationTargetKind kind : values()) {
                if (kind.name().equalsIgnoreCase(raw.trim())) {
                    return kind;
                }
            }
        }
        throw new IllegalArgumentException("Unknown target kind: " + raw);
    }
}
