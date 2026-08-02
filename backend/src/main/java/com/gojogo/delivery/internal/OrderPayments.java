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
 *               ESCROW ─── delivery fee ──▶ courier
 *               ESCROW ─── tip ──▶ courier
 *   cancelled   ESCROW ─── total ──▶ AVAILABLE
 * </pre>
 *
 * <p><b>The courier's two lines were the whole point of the arrangement 2e M3
 * left behind, and Phase 4 M1 is the line that changes.</b> Until couriers
 * existed, the delivery fee and the tip settled to the platform under their own
 * kinds ({@code COURIER_FEE}, {@code TIP}) rather than being folded into
 * commission — so redirecting them is a payee, and a year of tips does not have
 * to be un-picked out of platform revenue to find out what couriers were owed.
 *
 * <p>They still fall back to the platform when an order has no courier, which is
 * not dead code: every order delivered before this milestone had none, and a
 * split has to name <em>somebody</em> or the arithmetic below refuses to settle
 * and the money stays in escrow.
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
        // The courier's two lines, now that there is a courier.
        AccountRef courier = courierAccount(order);
        splits.add(new WalletApi.Split(courier, order.getDeliveryFeeCents(),
            LedgerKind.COURIER_FEE, "Delivery"));
        splits.add(new WalletApi.Split(courier, order.getTipCents(),
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
            courierAccount(order), amountCents, LedgerKind.TIP,
            WalletApi.Reference.of(REF_KIND, order.getId(), "Tip"),
            key(order, "tip:" + (order.getTipCents() + amountCents)));
        order.tipped(amountCents);
    }

    /**
     * Who the delivery fee and the tip belong to.
     *
     * <p>The platform fallback is for the orders that predate Phase 4 M1 and had
     * no courier at all — not a soft failure mode for one that should have. It
     * cannot be dropped: a split has to name an account, and refusing to settle
     * an old order would strand its money in escrow rather than surface anything.
     */
    private static AccountRef courierAccount(CustomerOrder order) {
        return order.getCourierUserId() == null
            ? AccountRef.platform()
            : AccountRef.user(order.getCourierUserId(), Bucket.AVAILABLE);
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
