package com.gojogo.messaging.internal;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * My World setup config (see application.yml). {@code devOtpCode}, when set,
 * is accepted by phone verification in addition to the real SMS code — it makes
 * the flow testable while the AWS account's SNS SMS is still in sandbox.
 *
 * <p><b>Defence in depth against the bypass it is.</b> A static code accepted
 * next to the real one is a universal phone-verification bypass the moment it
 * ships anywhere real, so it is honoured <em>only while SMS is disabled</em> —
 * i.e. only when nobody can receive a real code and the fallback is the sole way
 * through. Turn real SMS on ({@code smsEnabled}) and the dev code goes inert on
 * its own, no matter what {@code WORLD_OTP_DEV_CODE} is set to. A deploy that
 * sets both is a misconfiguration, and {@link #devCodeShipped()} lets startup
 * say so loudly rather than run a bypass in production.
 */
@ConfigurationProperties(prefix = "gojogo.world")
record WorldProperties(String devOtpCode, String smsSenderId, boolean smsEnabled) {

    /** Usable only when SMS is off — see the class note. */
    boolean hasDevCode() {
        return !smsEnabled && devOtpCode != null && !devOtpCode.isBlank();
    }

    /** A dev bypass code set while real SMS is on: inert, but wrong to ship, and
     *  worth a startup warning so it is caught before it is trusted. */
    boolean devCodeShipped() {
        return smsEnabled && devOtpCode != null && !devOtpCode.isBlank();
    }
}
