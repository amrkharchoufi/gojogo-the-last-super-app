package com.gojogo.payments.internal;

import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/**
 * Buying tokens, and seeing what you have.
 *
 * <p>Everything here is the caller's own, like the rest of {@code payments}:
 * there is no endpoint that reads another person's token balance and none that
 * moves tokens between people. A ride spends them by calling {@code TokenApi} on
 * the server.
 *
 * <p>What a <em>ride</em> costs in tokens is deliberately not on this surface —
 * that is priced by vehicle category and distance and lives on
 * {@code GET /v1/travel/tokens}, in the module that knows what a ride is.
 */
@RestController
class TokenController {

    private final TokenService tokens;
    private final PaymentsCurrentProfile current;

    TokenController(TokenService tokens, PaymentsCurrentProfile current) {
        this.tokens = tokens;
        this.current = current;
    }

    @GetMapping("/v1/payments/tokens")
    Dtos.TokenWalletDto myTokens(@AuthenticationPrincipal Jwt jwt) {
        return tokens.wallet(current.require(jwt).id());
    }

    /**
     * Buys a pack out of the wallet.
     *
     * <p>A short wallet comes back as a 402 carrying the shortfall — the global
     * handler's shape for {@code InsufficientFundsException} — so the app offers
     * a top-up for exactly the missing amount instead of a dead end. That is the
     * same path the driver stake takes, on purpose: one way for money to be
     * missing, one screen that fixes it.
     */
    @PostMapping("/v1/payments/tokens/purchase")
    Dtos.TokenWalletDto purchase(@AuthenticationPrincipal Jwt jwt,
                                 @Valid @RequestBody Dtos.TokenPurchaseRequest request) {
        return tokens.purchase(current.require(jwt).id(), request.packId());
    }
}
