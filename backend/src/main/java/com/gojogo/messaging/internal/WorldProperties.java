package com.gojogo.messaging.internal;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * My World setup config (see application.yml). {@code devOtpCode}, when set,
 * is accepted by phone verification in addition to the real SMS code — it makes
 * the flow testable while the AWS account's SNS SMS is still in sandbox. Leave
 * it unset in production.
 */
@ConfigurationProperties(prefix = "gojogo.world")
record WorldProperties(String devOtpCode, String smsSenderId, boolean smsEnabled) {

    boolean hasDevCode() {
        return devOtpCode != null && !devOtpCode.isBlank();
    }
}
