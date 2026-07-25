package com.gojogo.social.internal;

/** What a story frame actually is. Mirrors the V11 CHECK constraint. */
enum StoryMediaType {
    IMAGE,
    VIDEO,
    /** A caption on a colored card — no uploaded media at all. */
    TEXT;

    static StoryMediaType parse(String raw) {
        if (raw == null || raw.isBlank()) {
            return IMAGE;
        }
        try {
            return valueOf(raw.trim().toUpperCase(java.util.Locale.ROOT));
        } catch (IllegalArgumentException unknown) {
            return IMAGE;
        }
    }
}
