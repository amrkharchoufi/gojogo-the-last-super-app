package com.gojogo.profile.internal;

import java.util.Locale;

/** The one place a username is turned into its canonical form. */
final class Handles {

    static final int MIN_LENGTH = 2;

    private Handles() {
    }

    static String normalize(String raw) {
        String handle = raw.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9_.]", "");
        return handle.length() > 30 ? handle.substring(0, 30) : handle;
    }
}
