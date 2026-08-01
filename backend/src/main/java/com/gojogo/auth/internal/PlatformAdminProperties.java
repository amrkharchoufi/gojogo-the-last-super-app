package com.gojogo.auth.internal;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/**
 * The two ways into a platform operator surface (see
 * {@link com.gojogo.auth.PlatformAdminApi}).
 *
 * <p><b>The prefix says {@code partner} and that is deliberate.</b> These
 * settings were born with the KYC review queue in 2b M6 and are wired into the
 * live task definition as {@code PARTNER_ADMIN_TOKEN} / {@code PARTNER_ADMIN_GROUP};
 * renaming them here would be a code change that silently turns partner review
 * off in production on the next deploy. The name outlived its module — that is
 * cheaper than the alternative.
 */
@ConfigurationProperties(prefix = "gojogo.partner.admin")
record PlatformAdminProperties(String token, String group) {

    /** These endpoints see identity documents and can suspend accounts, so the
     *  bar is higher than the 16 characters the throwaway cleanup token settles
     *  for. */
    static final int MIN_TOKEN_LENGTH = 24;

    static final String DEFAULT_GROUP = "platform-admin";

    PlatformAdminProperties {
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
