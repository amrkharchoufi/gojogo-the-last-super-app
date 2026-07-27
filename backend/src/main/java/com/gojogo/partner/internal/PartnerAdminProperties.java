package com.gojogo.partner.internal;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/**
 * The review surface's key (see {@link PartnerAdminController}).
 *
 * <p>Unlike the economy cleanup token, this one is meant to <em>stay set</em>:
 * approving partners is an ongoing operational job, not a one-off wipe. It is
 * still off by default, so an environment nobody has configured cannot have its
 * applications decided by a stranger.
 */
@ConfigurationProperties(prefix = "gojogo.partner.admin")
record PartnerAdminProperties(String token) {

    /** These endpoints see identity documents, so the bar is higher than the
     *  16 characters the throwaway cleanup token settles for. */
    static final int MIN_TOKEN_LENGTH = 24;

    boolean enabled() {
        return token != null && token.length() >= MIN_TOKEN_LENGTH;
    }

    /** Set but unusable — worth a startup warning, since the operator thinks
     *  they turned review on and every path will still 404. */
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
