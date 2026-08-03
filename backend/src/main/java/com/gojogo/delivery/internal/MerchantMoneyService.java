package com.gojogo.delivery.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.payments.FeeApi;
import com.gojogo.payments.OwnerKind;
import com.gojogo.payments.PayoutApi;
import com.gojogo.payments.WalletApi;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.UUID;

/**
 * A restaurant's own money: what it has earned, and how to get it out.
 *
 * <p>Lives in {@code delivery} rather than in {@code payments} for a reason
 * worth recording. A merchant's balance is a payments concept, but "is this
 * caller allowed to see it" is a <em>delivery</em> fact — the ownership stamp on
 * the merchant row. Putting these endpoints in payments would mean payments
 * asking delivery who owns a merchant, and delivery already depends on payments;
 * the cycle would be immediate. So the vertical that owns the payee owns the
 * surface, calls {@code WalletApi}/{@code PayoutApi} with an owner reference,
 * and payments never learns what a restaurant is. Phase 3's drivers arrive the
 * same way (ARCHITECTURE §10b: no admin-only mirror of the {@code /mine}
 * endpoints).
 */
@Service
class MerchantMoneyService {

    private static final String PAYOUT_MIN_KEY = "payments.payout.min.minor";
    private static final long PAYOUT_MIN_DEFAULT = 1_000;

    private final MerchantRepository merchants;
    private final PromotionService promotions;
    private final WalletApi wallet;
    private final PayoutApi payouts;
    private final FeeApi fees;
    private final ConfigApi config;

    MerchantMoneyService(MerchantRepository merchants, PromotionService promotions,
                         WalletApi wallet, PayoutApi payouts, FeeApi fees, ConfigApi config) {
        this.merchants = merchants;
        this.promotions = promotions;
        this.wallet = wallet;
        this.payouts = payouts;
        this.fees = fees;
        this.config = config;
    }

    @Transactional(readOnly = true)
    MerchantWalletDto wallet(UUID me) {
        Merchant merchant = require(me);
        WalletApi.Balances balances = wallet.balancesOf(OwnerKind.MERCHANT, merchant.getId());
        PayoutApi.ConnectStatus connect = payouts.statusOf(OwnerKind.MERCHANT, merchant.getId());
        List<TransactionLineDto> recent = wallet
            .statement(OwnerKind.MERCHANT, merchant.getId(), 25).stream()
            .map(entry -> new TransactionLineDto(entry.id(), entry.amountMinor(),
                entry.kind().name(), entry.memo(), entry.createdAt()))
            .toList();
        return new MerchantWalletDto(balances.available(), balances.currency(),
            fees.policyFor(FeeApi.DELIVERY).percentBps(),
            connect.exists(), connect.ready(), connect.requirementsNote(),
            config.number(PAYOUT_MIN_KEY, PAYOUT_MIN_DEFAULT), recent);
    }

    /**
     * A Stripe-hosted onboarding link for this restaurant's payouts.
     *
     * <p>Single-use and short-lived by Stripe's design, so it is minted on
     * demand and never stored: whoever opens it is treated as the account
     * holder.
     */
    @Transactional
    String onboardingLink(UUID me, String email) {
        Merchant merchant = require(me);
        return payouts.onboardingLink(OwnerKind.MERCHANT, merchant.getId(), email);
    }

    /**
     * Sends earnings to the connected account. The owner asks; the merchant is
     * paid.
     *
     * <p>Deliberately not {@code @Transactional}: a payout is two transactions
     * on purpose (debit, then transfer), and wrapping it in a third would undo
     * that — a crash mid-transfer would roll the debit back and leave money that
     * may already be in flight looking as though it never left.
     */
    PayoutDto payOut(UUID me, long amountMinor) {
        Merchant merchant = require(me);
        // No earned-cap: a merchant balance is only ever earnings, never a card
        // top-up, so there is no card-in/bank-out path to bound. The cooldown and
        // the balance still serialize under the payout's lock, which is what
        // keeps two concurrent requests from each clearing the once-a-day gate.
        PayoutApi.PayoutResult result = payouts.payOut(OwnerKind.MERCHANT, merchant.getId(),
            me, amountMinor, PayoutApi.PayoutGuard.none());
        return new PayoutDto(result.payoutId(), result.amountMinor(), result.currency(),
            result.status(), result.failureReason());
    }

    // MARK: Promotions

    @Transactional(readOnly = true)
    List<PromotionDto> promotions(UUID me) {
        return promotions.forMerchant(require(me).getId());
    }

    @Transactional
    PromotionDto createPromotion(UUID me, SavePromotionRequest request) {
        return promotions.create(require(me).getId(), request);
    }

    @Transactional
    void endPromotion(UUID me, UUID promotionId) {
        promotions.deactivate(require(me).getId(), promotionId);
    }

    /** 404, not 403 — the same answer this module gives everywhere for a
     *  restaurant that isn't yours: you have no restaurant here. */
    private Merchant require(UUID me) {
        return merchants.findFirstByOwnerId(me).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "You don't manage a restaurant"));
    }
}
