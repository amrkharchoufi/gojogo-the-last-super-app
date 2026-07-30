package com.gojogo.kyc.internal;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The applicant's three verbs. Everything here is scoped to the caller: there
 * is no endpoint that reads someone else's identity check, by design — a
 * reviewer sees a status through the {@code partner} admin surface, and nobody
 * sees the documents at all.
 */
@RestController
class KycController {

    private final KycService kyc;
    private final KycCurrentProfile current;

    KycController(KycService kyc, KycCurrentProfile current) {
        this.kyc = kyc;
        this.current = current;
    }

    /** Where this person stands. Cheap and local — no vendor call. */
    @GetMapping("/v1/kyc/me")
    IdentityVerificationDto mine(@AuthenticationPrincipal Jwt jwt) {
        return kyc.mine(current.require(jwt).id());
    }

    /**
     * A fresh SDK access token.
     *
     * <p>Called both to launch the flow and, through the SDK's expiration
     * handler, to keep it alive — so it is a POST that is expected to be
     * repeated, and it neither resets a verification nor starts a second one.
     */
    @PostMapping("/v1/kyc/access-token")
    AccessTokenResponse accessToken(@AuthenticationPrincipal Jwt jwt) {
        return kyc.startVerification(current.require(jwt).id());
    }

    /**
     * Asks the vendor where this person stands, rather than waiting to be told.
     *
     * <p>What the app calls the moment the SDK closes. Without it the flow would
     * depend on a webhook — which needs a public URL configured in someone
     * else's console — and a user who had just finished verifying would be shown
     * a stale "not started" until it arrived.
     */
    @PostMapping("/v1/kyc/refresh")
    IdentityVerificationDto refresh(@AuthenticationPrincipal Jwt jwt) {
        return kyc.refresh(current.require(jwt).id());
    }
}
