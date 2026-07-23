package com.gojogo.notifications.internal;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * APNs config (see application.yml). All empty by default → push disabled and
 * the sender no-ops (same gating pattern as the World SMS dev fallback), so the
 * app deploys and runs before an Apple push key exists. {@code keyBase64} is the
 * base64 of the .p8 token-auth key file; {@code production} picks the APNs host.
 */
@ConfigurationProperties(prefix = "gojogo.apns")
record ApnsProperties(String keyId, String teamId, String bundleId,
                      String keyBase64, boolean production) {

    boolean enabled() {
        return present(keyId) && present(teamId) && present(bundleId) && present(keyBase64);
    }

    String host() {
        return production ? "api.push.apple.com" : "api.sandbox.push.apple.com";
    }

    private static boolean present(String s) {
        return s != null && !s.isBlank();
    }
}
