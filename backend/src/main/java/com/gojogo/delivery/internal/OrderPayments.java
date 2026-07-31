package com.gojogo.delivery.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.payments.AccountRef;
import com.gojogo.payments.Bucket;
import com.gojogo.payments.FeeApi;
import com.gojogo.payments.LedgerKind;
import com.gojogo.payments.OwnerKind;
import com.gojogo.payments.WalletApi;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * Delivery's whole relationship with money — every call into {@code WalletApi}
 * this vertical makes is in this file.
 *
 * <p>Kept out of {@code DeliveryService} deliberately: that class already owns
 * the catalog, addresses, orders and fulfilment, and settlement is the one part
 * where a mistake is expensive rather than annoying. It is worth being able to
 * read all of it at once.
 *
 * <p>The shape of an order's money:
 *
 * <pre>
 *   placement   AVAILABLE ─── total ──▶ ESCROW          (the customer's, still)
 *   delivered   ESCROW ─── food − commission ──▶ merchant
 *               ESCROW ─── commission + service fee ──▶ platform
 *               ESCROW ─── delivery fee ──▶ platform     (the courier's, Phase 4)
 *               ESCROW ─── tip ──▶ platform              (the courier's, Phase 4)
 *   cancelled   ESCROW ─── total ──▶ AVAILABLE
 * </pre>
 *
 * <p>The two payees that don't exist yet settle to the platform under their own
 * ledger kinds ({@code COURIER_FEE}, {@code TIP}) rather than being folded into
 * the commission. When Phase 4 M1 gives couriers accounts, redirecting them is
 * one line here and the history stays readable — which it would not be if a
 * year of tips had been recorded as platform revenue.
 */
@Service
class OrderPayments {

    private static final Logger log = LoggerFactory.getLogger(OrderPayments.class);

    /** Whether an order must be paid for at all. True in every real
     *  environment; the knob exists so a deployment with no wallet funding
     *  path can still exercise the vertical, the same way an unconfigured KYC
     *  vendor falls back rather than blocking onboarding. */
    private static final String REQUIRED_KEY = "delivery.checkout.wallet.required";
    private static final String REF_KIND = "ORDER";

    private final WalletApi wallet;
    private final FeeApi fees;
    private final ConfigApi config;

    OrderPayments(WalletApi wallet, FeeApi fees, ConfigApi config) {
        this.wallet = wallet;
        this.fees = fees;
        this.config = config;
    }

    boolean required() {
        return config.flag(REQUIRED_KEY, true);
    }

    long availableFor(UUID userId) {
        return wallet.balancesOf(OwnerKind.USER, userId).available();
    }

    String currency() {
        return wallet.currency();
    }

    /**
     * Takes the money out of circulation at checkout.
     *
     * <p>Throws {@link com.gojogo.payments.InsufficientFundsException} when the
     * wallet is short, which the global handler turns into a 402 — the status
     * the app reads to offer a top-up rather than an apology.
     */
    void hold(CustomerOrder order, String merchantName) {
        if (!required() || order.getTotalCents() <= 0) return;
        wallet.hold(OwnerKind.USER, order.getUserId(), order.getTotalCents(),
            WalletApi.Reference.of(REF_KIND, order.getId(), merchantName),
            key(order, "hold"));
        order.held(OffsetDateTime.now());
    }

    /**
     * Splits the hold at delivery. Idempotent on the order, so the fulfilment
     * job passing through DELIVERED twice cannot pay a merchant twice.
     */
    void settle(CustomerOrder order, String merchantName) {
        if (order.getPaymentStatus() != PaymentStatus.HELD) return;

        int merchantBase = order.getSubtotalCents() - order.getDiscountCents();
        long commission = fees.platformFee(FeeApi.DELIVERY, merchantBase);
        long platformTake = commission + order.getServiceFeeCents();

        List<WalletApi.Split> splits = new ArrayList<>(4);
        splits.add(new WalletApi.Split(
            AccountRef.merchant(order.getMerchantId(), Bucket.AVAILABLE),
            merchantBase - commission, LedgerKind.CAPTURE, merchantName));
        splits.add(new WalletApi.Split(AccountRef.platform(), platformTake,
            LedgerKind.FEE, "Service + commission"));
        // The courier's two lines. Held by the platform until Phase 4 M1 gives
        // couriers accounts — same kinds, different payee, one line changes.
        splits.add(new WalletApi.Split(AccountRef.platform(), order.getDeliveryFeeCents(),
            LedgerKind.COURIER_FEE, "Delivery"));
        splits.add(new WalletApi.Split(AccountRef.platform(), order.getTipCents(),
            LedgerKind.TIP, "Tip"));

        long sum = splits.stream().mapToLong(WalletApi.Split::amountMinor).sum();
        if (sum != order.getTotalCents()) {
            // Impossible unless the arithmetic in Basket and the arithmetic here
            // have drifted. Refusing beats stranding the difference in escrow
            // where nobody would notice it for a month.
            log.error("Order {} splits sum to {} but {} was held — not settling",
                order.getId(), sum, order.getTotalCents());
            return;
        }

        wallet.capture(OwnerKind.USER, order.getUserId(), splits,
            WalletApi.Reference.of(REF_KIND, order.getId(), merchantName), key(order, "capture"));
        order.settled(OffsetDateTime.now());
    }

    /** Gives it all back. The order was cancelled before the courier moved. */
    void release(CustomerOrder order) {
        if (order.getPaymentStatus() != PaymentStatus.HELD) return;
        wallet.release(OwnerKind.USER, order.getUserId(), order.getTotalCents(),
            WalletApi.Reference.of(REF_KIND, order.getId(), "Order cancelled"),
            key(order, "release"));
        order.releasedFunds(OffsetDateTime.now());
    }

    /**
     * A tip added after the food arrived, paid straight through rather than
     * through escrow: there is nothing left to hold it against, and the courier
     * has already done the work.
     *
     * <p>The idempotency key carries the running tip total, so tipping twice is
     * two movements while a retried request is one.
     */
    void tipAfterDelivery(CustomerOrder order, int amountCents) {
        if (!required() || amountCents <= 0) return;
        wallet.transfer(AccountRef.user(order.getUserId(), Bucket.AVAILABLE),
            AccountRef.platform(), amountCents, LedgerKind.TIP,
            WalletApi.Reference.of(REF_KIND, order.getId(), "Tip"),
            key(order, "tip:" + (order.getTipCents() + amountCents)));
        order.tipped(amountCents);
    }

    /** What the merchant actually earned on an order, for their dashboard. */
    long merchantEarningsOn(CustomerOrder order) {
        int base = order.getSubtotalCents() - order.getDiscountCents();
        return base - fees.platformFee(FeeApi.DELIVERY, base);
    }

    private static String key(CustomerOrder order, String verb) {
        return "order:" + order.getId() + ":" + verb;
    }
}
