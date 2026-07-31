package com.gojogo.payments.internal;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/**
 * Stripe credentials and the two URLs a hosted checkout has to come back to.
 *
 * <p>Everything is empty by default, and empty means <em>off</em> — the same
 * posture as Sumsub and APNs, and it matters more here than anywhere else: the
 * ledger is entirely internal, so an environment with no Stripe keys can still
 * hold, capture, release and transfer every cent. What it cannot do is take
 * money in from a card or send any out. That is a mode, not a failure.
 *
 * @param secretKey      signs our calls out. {@code sk_test_} is test mode, and
 *                       the key prefix is the only difference between charging
 *                       nobody and charging everybody — hence the startup log.
 * @param webhookSecret  verifies Stripe's calls in. A <b>different</b> secret,
 *                       minted when the endpoint is created in the dashboard,
 *                       which is why it is legitimately empty on a first deploy:
 *                       the endpoint has to exist before it can have one.
 * @param publishableKey handed to the iOS client. Public by design, kept here so
 *                       one rotation touches one place.
 * @param returnBaseUrl  where Stripe sends the customer's browser afterwards.
 *                       Must be this API's own public origin: Checkout refuses
 *                       a custom URL scheme, so the round trip back into the app
 *                       goes through a page this backend serves.
 */
@ConfigurationProperties(prefix = "gojogo.payments.stripe")
record StripeProperties(String baseUrl, String secretKey, String webhookSecret,
                        String publishableKey, String returnBaseUrl, String appScheme) {

    static final String DEFAULT_BASE_URL = "https://api.stripe.com";
    static final String DEFAULT_APP_SCHEME = "gojogo";

    StripeProperties {
        baseUrl = blank(baseUrl) ? DEFAULT_BASE_URL : baseUrl.trim().replaceAll("/+$", "");
        secretKey = blank(secretKey) ? "" : secretKey.trim();
        webhookSecret = blank(webhookSecret) ? "" : webhookSecret.trim();
        publishableKey = blank(publishableKey) ? "" : publishableKey.trim();
        returnBaseUrl = blank(returnBaseUrl) ? "" : returnBaseUrl.trim().replaceAll("/+$", "");
        appScheme = blank(appScheme) ? DEFAULT_APP_SCHEME : appScheme.trim();
    }

    /** Whether external money can move at all. */
    boolean enabled() {
        return !secretKey.isEmpty();
    }

    /**
     * Whether an inbound webhook can be authenticated. Separate from
     * {@link #enabled()} on purpose: with a secret key but no webhook secret the
     * platform can create a Checkout session and take the customer's money, and
     * then has no trustworthy way to learn that it did. So the top-up endpoint
     * refuses to start a payment it could not finish, rather than stranding one.
     */
    boolean webhooksEnabled() {
        return !webhookSecret.isEmpty();
    }

    /** Test-mode keys are prefixed {@code sk_test_}. Worth saying out loud at
     *  startup, because nothing else about the integration looks different. */
    boolean testMode() {
        return secretKey.startsWith("sk_test_") || secretKey.startsWith("rk_test_");
    }

    /** Constant-time, so a forged signature leaks nothing through timing. */
    boolean digestMatches(String expected, String presented) {
        return presented != null && MessageDigest.isEqual(
            expected.getBytes(StandardCharsets.UTF_8),
            presented.getBytes(StandardCharsets.UTF_8));
    }

    private static boolean blank(String value) {
        return value == null || value.isBlank();
    }
}
