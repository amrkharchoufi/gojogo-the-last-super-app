package com.gojogo.partner.internal;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/**
 * Who may work the review queue (see {@link PartnerAdminController}).
 *
 * <p>Two ways in, deliberately unequal:
 * <ul>
 *   <li><b>{@code group}</b> — a real operator identity: a Cognito group
 *       (default {@code platform-admin}) that arrives in the reviewer's own ID
 *       token as a {@code cognito:groups} claim. This is what GoJoAdmin signs
 *       in with, and it is <em>attributable</em> — every decision can name a
 *       person.</li>
 *   <li><b>{@code token}</b> — break-glass: one shared secret, no identity, for
 *       the operator with no console and for the day Cognito is the broken
 *       thing. Kept because losing the ability to approve partners takes
 *       GojoDelivery's supply side down with it.</li>
 * </ul>
 *
 * <p>Both are off by default, so an environment nobody has configured cannot
 * have its applications decided by a stranger.
 */
@ConfigurationProperties(prefix = "gojogo.partner.admin")
record PartnerAdminProperties(String token, String group) {

    /** These endpoints see identity documents, so the bar is higher than the
     *  16 characters the throwaway cleanup token settles for. */
    static final int MIN_TOKEN_LENGTH = 24;

    static final String DEFAULT_GROUP = "platform-admin";

    PartnerAdminProperties {
        group = group == null || group.isBlank() ? DEFAULT_GROUP : group.trim();
    }

    boolean tokenEnabled() {
        return token != null && token.length() >= MIN_TOKEN_LENGTH;
    }

    /** Set but unusable — worth a startup warning, since the operator thinks
     *  they turned review on and every path will still 404. */
    boolean tooShort() {
        return !tokenEnabled() && token != null && !token.isBlank();
    }

    /** Constant-time so a wrong token leaks nothing through timing. */
    boolean matches(String presented) {
        return tokenEnabled() && presented != null && MessageDigest.isEqual(
            token.getBytes(StandardCharsets.UTF_8),
            presented.getBytes(StandardCharsets.UTF_8));
    }
}
