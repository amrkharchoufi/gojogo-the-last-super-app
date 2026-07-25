package com.gojogo.social.internal;

/** Who a story frame is visible to. Mirrors the V11 CHECK constraint. */
enum StoryAudience {
    /** Everyone who follows the author (plus the author). */
    ALL,
    /** Only the author's close friends — see {@code social.close_friend} (V13). */
    CLOSE_FRIENDS;

    static StoryAudience parse(String raw) {
        if (raw == null || raw.isBlank()) {
            return ALL;
        }
        try {
            return valueOf(raw.trim().toUpperCase(java.util.Locale.ROOT));
        } catch (IllegalArgumentException unknown) {
            return ALL;
        }
    }
}
