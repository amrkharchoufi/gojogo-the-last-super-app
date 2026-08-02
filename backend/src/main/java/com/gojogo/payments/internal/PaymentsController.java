package com.gojogo.payments.internal;

import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * The person's own wallet. Everything here is scoped to the caller — there is no
 * endpoint that reads someone else's balance, and no endpoint that moves money
 * between people. A vertical moves money by calling {@code WalletApi} on the
 * server, never by the client asking for a transfer.
 *
 * <p>Merchant balances and payouts deliberately live on the vertical's own
 * {@code /mine} surface (delivery's, today) rather than here: only the module
 * that owns a merchant can prove the caller owns it, and payments asking would
 * be a dependency in the wrong direction.
 */
@RestController
class PaymentsController {

    private final PaymentsService payments;
    private final PaymentsCurrentProfile current;
    private final ExchangeRateService rates;

    PaymentsController(PaymentsService payments, PaymentsCurrentProfile current,
                       ExchangeRateService rates) {
        this.payments = payments;
        this.current = current;
        this.rates = rates;
    }

    /**
     * What the platform's money is worth where the caller lives, so a price can
     * be shown in a currency they think in.
     *
     * <p>Identical for every caller, because it is a rate table and not an
     * account: a per-user rate would suggest the conversion has something to do
     * with them, and the next question after that is why their dollar is worth
     * less than somebody else's. It stays behind the same authentication as
     * everything else on this surface — every screen that shows money is signed
     * in already, so there is nothing to gain from opening a new public path.
     * Which rate to use is the app's decision, from the device's own region.
     *
     * <p>Nothing here changes what anybody is charged. Every amount that moves
     * moves in {@code base}; these numbers exist so a driver in Casablanca knows
     * whether a $30 stake is a lot.
     */
    @GetMapping("/v1/payments/rates")
    Dtos.RatesDto rates() {
        return rates.snapshot();
    }

    @GetMapping("/v1/payments/wallet")
    Dtos.WalletDto wallet(@AuthenticationPrincipal Jwt jwt) {
        return payments.wallet(current.require(jwt).id());
    }

    /** The statement. Movements between the caller's own buckets are left out —
     *  a hold is bookkeeping, not a transaction they made. */
    @GetMapping("/v1/payments/transactions")
    List<Dtos.TransactionDto> transactions(@AuthenticationPrincipal Jwt jwt,
                                           @RequestParam(defaultValue = "50") int limit) {
        return payments.statement(current.require(jwt).id(), limit);
    }

    /**
     * Starts a card top-up and hands back a Stripe-hosted URL to open.
     *
     * <p>The wallet is credited by the webhook, not by the customer coming back
     * from that URL, so this endpoint moves no money and is safe to call twice.
     */
    @PostMapping("/v1/payments/topups")
    Dtos.TopUpResponse topUp(@AuthenticationPrincipal Jwt jwt,
                             @Valid @RequestBody Dtos.TopUpRequest request) {
        return payments.startTopUp(current.require(jwt).id(), request.amountMinor());
    }

    @GetMapping("/v1/payments/topups")
    List<Dtos.TopUpDto> topUps(@AuthenticationPrincipal Jwt jwt,
                               @RequestParam(defaultValue = "20") int limit) {
        return payments.recentTopUps(current.require(jwt).id(), limit);
    }

    /**
     * Asks Stripe what happened to one top-up, rather than waiting to be told.
     *
     * <p>What the app calls when it comes back from the checkout sheet. The same
     * shape as {@code POST /v1/kyc/refresh} and for the same reason: a flow that
     * only completes when someone else's webhook console is configured correctly
     * is a flow that fails silently.
     */
    @PostMapping("/v1/payments/topups/{paymentId}/refresh")
    Dtos.TopUpDto refresh(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID paymentId) {
        return payments.reconcile(current.require(jwt).id(), paymentId);
    }

}
