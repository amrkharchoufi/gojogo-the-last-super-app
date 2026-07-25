package com.gojogo.watch.internal;

/**
 * Which feed a video belongs to. One table serves both — they differ in how the
 * client presents them (16:9 page vs full-bleed vertical pager), not in
 * anything the server does with them.
 */
enum VideoKind {
    LONG_FORM,
    SHORT;

    /** Lenient parse of the wire value; anything unrecognised is long-form. */
    static VideoKind parse(String raw) {
        if (raw == null) {
            return LONG_FORM;
        }
        return switch (raw.trim().toUpperCase(java.util.Locale.ROOT)) {
            case "SHORT", "SHORTS" -> SHORT;
            default -> LONG_FORM;
        };
    }
}
