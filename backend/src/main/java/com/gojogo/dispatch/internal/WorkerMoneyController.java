package com.gojogo.dispatch.internal;

import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * The worker's money, on the same {@code /me} terms as the rest of this module:
 * no id in the path, so there is nothing to authorise beyond "are you one".
 *
 * <p>A second controller rather than three more methods on
 * {@link DispatchController}, because they are answers to different questions.
 * That one is the offer book — the highest-frequency, lowest-consequence surface
 * in the system, called every few seconds by a phone on a motorbike. This one is
 * money, called when somebody opens a screen on purpose, and the two should not
 * share a class whose comments have to keep saying which is which.
 *
 * <p>Driver and courier are served by the same three endpoints on purpose: a
 * dual-mode person has one wallet. See {@link WorkerMoneyService} for why the
 * surface is here at all, and for the cap on what may leave.
 *
 * <pre>
 * # what I've earned, what I can take out, and whether payouts are set up
 * curl -H "Authorization: Bearer $JWT" https://api.gojogo.app/v1/dispatch/me/wallet
 *
 * # set payouts up (single-use link — call it again next time)
 * curl -X POST -H "Authorization: Bearer $JWT" \
 *   https://api.gojogo.app/v1/dispatch/me/payouts/onboarding
 *
 * # take $25 out. 409 with the ceiling if that's more than you've earned,
 * # 402 if the wallet is short
 * curl -X POST -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' \
 *   -d '{"amountMinor":2500}' https://api.gojogo.app/v1/dispatch/me/payouts
 * </pre>
 */
@RestController
class WorkerMoneyController {

    private final WorkerMoneyService money;
    private final DispatchCurrentProfile current;

    WorkerMoneyController(WorkerMoneyService money, DispatchCurrentProfile current) {
        this.money = money;
        this.current = current;
    }

    /** Balance, lifetime earnings, what of it is withdrawable, whether payouts
     *  are set up, and the last 25 lines — everything the screen needs in one
     *  read. */
    @GetMapping("/v1/dispatch/me/wallet")
    WorkerWalletDto wallet(@AuthenticationPrincipal Jwt jwt) {
        return money.wallet(current.require(jwt).id());
    }

    /** A fresh Stripe onboarding link. Single-use, so this is a POST that is
     *  expected to be called again. */
    @PostMapping("/v1/dispatch/me/payouts/onboarding")
    Map<String, String> onboardingLink(@AuthenticationPrincipal Jwt jwt) {
        return Map.of("url", money.onboardingLink(current.require(jwt).id(),
            jwt.getClaimAsString("email")));
    }

    @PostMapping("/v1/dispatch/me/payouts")
    WorkerPayoutDto payOut(@AuthenticationPrincipal Jwt jwt,
                           @Valid @RequestBody WorkerPayoutRequest request) {
        return money.payOut(current.require(jwt).id(), request.amountMinor());
    }
}
