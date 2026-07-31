package com.gojogo.delivery.internal;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * The restaurant owner's money and campaigns, on the same {@code /mine} terms as
 * the menu editor: no id in the path, so there is nothing to authorise beyond
 * "do you own one".
 *
 * <p>This is the surface GoJoAdmin's Economy module calls with the owner's own
 * JWT (ARCHITECTURE §10b) — there is deliberately no admin-only mirror of it.
 */
@RestController
class MerchantMoneyController {

    private final MerchantMoneyService money;
    private final DeliveryCurrentProfile current;

    MerchantMoneyController(MerchantMoneyService money, DeliveryCurrentProfile current) {
        this.money = money;
        this.current = current;
    }

    /** Earnings, the commission they were charged, and whether payouts are set
     *  up — everything the dashboard needs in one read. */
    @GetMapping("/v1/delivery/merchants/mine/wallet")
    MerchantWalletDto wallet(@AuthenticationPrincipal Jwt jwt) {
        return money.wallet(current.require(jwt).id());
    }

    /** A fresh Stripe onboarding link. Single-use, so this is a POST that is
     *  expected to be called again. */
    @PostMapping("/v1/delivery/merchants/mine/payouts/onboarding-link")
    Map<String, String> onboardingLink(@AuthenticationPrincipal Jwt jwt) {
        return Map.of("url", money.onboardingLink(current.require(jwt).id(),
            jwt.getClaimAsString("email")));
    }

    @PostMapping("/v1/delivery/merchants/mine/payouts")
    PayoutDto payOut(@AuthenticationPrincipal Jwt jwt,
                     @Valid @RequestBody PayoutRequestBody request) {
        return money.payOut(current.require(jwt).id(), request.amountMinor());
    }

    @GetMapping("/v1/delivery/merchants/mine/promotions")
    List<PromotionDto> promotions(@AuthenticationPrincipal Jwt jwt) {
        return money.promotions(current.require(jwt).id());
    }

    @PostMapping("/v1/delivery/merchants/mine/promotions")
    @ResponseStatus(HttpStatus.CREATED)
    PromotionDto createPromotion(@AuthenticationPrincipal Jwt jwt,
                                 @Valid @RequestBody SavePromotionRequest request) {
        return money.createPromotion(current.require(jwt).id(), request);
    }

    /** Ends a promotion rather than deleting it — orders reference it, and a
     *  campaign that vanishes takes its own results with it. */
    @DeleteMapping("/v1/delivery/merchants/mine/promotions/{promotionId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void endPromotion(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID promotionId) {
        money.endPromotion(current.require(jwt).id(), promotionId);
    }
}
