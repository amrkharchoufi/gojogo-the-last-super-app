package com.gojogo.economy.internal;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/**
 * Dev-only marketplace cleanup config (see {@link EconomyAdminController}).
 *
 * <p>The cleanup endpoints exist only while {@code token} is set to something at
 * least {@link #MIN_TOKEN_LENGTH} characters long. Unset — the default, and what
 * production runs with — every path under {@code /v1/economy/admin} answers 404
 * like any other unmapped URL. Set {@code ECONOMY_ADMIN_TOKEN} for the deploy
 * that does the wipe, then unset it and deploy again.
 */
@ConfigurationProperties(prefix = "gojogo.economy.admin")
record EconomyAdminProperties(String token) {

    /** Short enough to type, long enough not to be guessed off a 404. */
    static final int MIN_TOKEN_LENGTH = 16;

    boolean enabled() {
        return token != null && token.length() >= MIN_TOKEN_LENGTH;
    }

    /** Set but unusable — worth a startup warning, since the operator thinks
     *  they turned cleanup on and the endpoints will still 404. */
    boolean tooShort() {
        return !enabled() && token != null && !token.isBlank();
    }

    /** Constant-time so a wrong token leaks nothing through timing. */
    boolean matches(String presented) {
        return enabled() && presented != null && MessageDigest.isEqual(
            token.getBytes(StandardCharsets.UTF_8),
            presented.getBytes(StandardCharsets.UTF_8));
    }
}
