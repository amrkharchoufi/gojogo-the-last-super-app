package com.gojogo.kyc.internal;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/**
 * Sumsub credentials and the one product decision that lives in config: which
 * verification level an applicant is put through.
 *
 * <p>Everything is empty by default, and empty means <em>off</em> — the same
 * posture as APNs. An unconfigured environment does not half-verify people; it
 * falls back to the human document review {@code partner} has always had.
 *
 * @param appToken   the {@code X-App-Token}. A sandbox token is prefixed
 *                   {@code sbx:}; the API host is the same either way, so the
 *                   token alone decides which environment this talks to.
 * @param secretKey  signs every outbound request (HMAC-SHA256).
 * @param webhookSecret signs <em>inbound</em> webhooks. A <b>different</b>
 *                   secret, set when the webhook is created in the Sumsub
 *                   cockpit — conflating the two is how an integration ends up
 *                   accepting forged verdicts.
 * @param levelName  must name a level that exists in the cockpit.
 * @param tokenTtlSeconds how long an SDK access token stays valid. Short on
 *                   purpose: the SDK asks for a fresh one through its
 *                   expiration handler, so a leaked token is worth little.
 */
@ConfigurationProperties(prefix = "gojogo.kyc.sumsub")
record SumsubProperties(String baseUrl, String appToken, String secretKey,
                        String webhookSecret, String levelName, int tokenTtlSeconds) {

    static final String DEFAULT_BASE_URL = "https://api.sumsub.com";
    static final String DEFAULT_LEVEL = "id-and-liveness";
    static final int DEFAULT_TTL_SECONDS = 600;

    SumsubProperties {
        baseUrl = blank(baseUrl) ? DEFAULT_BASE_URL : baseUrl.trim().replaceAll("/+$", "");
        appToken = blank(appToken) ? "" : appToken.trim();
        secretKey = blank(secretKey) ? "" : secretKey.trim();
        webhookSecret = blank(webhookSecret) ? "" : webhookSecret.trim();
        levelName = blank(levelName) ? DEFAULT_LEVEL : levelName.trim();
        tokenTtlSeconds = tokenTtlSeconds <= 0 ? DEFAULT_TTL_SECONDS : tokenTtlSeconds;
    }

    /** Both halves of the API credential, or nothing. One without the other
     *  cannot sign a request, so it is not a partially-working integration. */
    boolean enabled() {
        return !appToken.isEmpty() && !secretKey.isEmpty();
    }

    /**
     * Whether inbound webhooks can be authenticated. Kept separate from
     * {@link #enabled()} because the two are configured at different times: the
     * API credential is a secret you paste, the webhook secret only exists once
     * this backend has a public URL to point a webhook at. Until then the pull
     * path ({@code POST /v1/kyc/refresh}) carries the flow on its own.
     */
    boolean webhooksEnabled() {
        return !webhookSecret.isEmpty();
    }

    /** True in the Sumsub sandbox, which is worth saying out loud at startup —
     *  sandbox verdicts are simulated and mean nothing about a real person. */
    boolean sandbox() {
        return appToken.startsWith("sbx:");
    }

    /** Constant-time, so a forged digest leaks nothing through timing. */
    boolean digestMatches(String expected, String presented) {
        return presented != null && MessageDigest.isEqual(
            expected.getBytes(StandardCharsets.UTF_8),
            presented.getBytes(StandardCharsets.UTF_8));
    }

    private static boolean blank(String value) {
        return value == null || value.isBlank();
    }
}
