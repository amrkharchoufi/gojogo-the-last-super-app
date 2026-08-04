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
import java.util.Map;
import java.util.UUID;

/**
 * Delivery's whole relationship with money — every call into {@code WalletApi}
 * this vertical makes is in this file.
 *
 * <p>Kept out of {@code DeliveryService} deliberately: that class already owns
 * the catalog, addresses, quoting and placement, and settlement is the one part
 * where a mistake is expensive rather than annoying. It is worth being able to
 * read all of it at once.
 *
 * <p>The shape of an order's money, since Phase 4 M3 with a merchant subscript:
 *
 * <pre>
 *   placement    AVAILABLE ─── total ──▶ ESCROW           (the customer's, still)
 *   sub cancel   ESCROW ─── that slice's share ──▶ AVAILABLE
 *   delivered    ESCROW ─── food_i − commission_i ──▶ merchant_i   (per live slice)
 *                ESCROW ─── Σ commission + service fee ──▶ platform
 *                ESCROW ─── Σ delivery fees ──▶ courier
 *                ESCROW ─── tip ──▶ courier
 *   cancelled    ESCROW ─── whatever is left ──▶ AVAILABLE
 * </pre>
 *
 * <p><b>The invariant is unchanged and now has a second term:</b> what the
 * settlement splits plus what per-sub-order cancellations already released must
 * equal what was held, to the cent, or nothing settles. A slice's share is
 * always {@code subtotal − discount + its delivery fee}; the service fee and
 * the tip belong to the order and only move at the end, whichever end that is.
 *
 * <p>The courier's lines still fall back to the platform when an order has no
 * courier, which is not dead code: every order delivered before Phase 4 M1 had
 * none, and a split has to name <em>somebody</em> or the money stays in escrow.
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
    void hold(CustomerOrder order, String memo) {
        if (!required() || order.getTotalCents() <= 0) return;
        wallet.hold(OwnerKind.USER, order.getUserId(), order.getTotalCents(),
            WalletApi.Reference.of(REF_KIND, order.getId(), memo),
            key(order, "hold"));
        order.held(OffsetDateTime.now());
    }

    /**
     * Moves the hold to what the order now costs, after a change (Phase 4 M5).
     *
     * <p>A difference rather than a release-and-re-hold: the two would show up
     * on the customer's statement as a refund and a second charge for an order
     * they never stopped having, and a failure between them would leave the
     * escrow empty on a live order. One movement, in whichever direction, and
     * a bigger basket that the wallet cannot cover throws
     * {@link com.gojogo.payments.InsufficientFundsException} before anything on
     * the order is saved — the same 402 checkout gives, at the same moment it
     * still means something.
     *
     * <p>The key carries the revision, so a customer who changes their mind
     * three times moves money three times while a retried request moves it
     * once.
     */
    void adjustHold(CustomerOrder order, int previousTotalCents, String memo) {
        if (!required()) return;
        if (order.getPaymentStatus() != PaymentStatus.HELD) {
            // Nothing was ever held, because there was nothing to hold. Rare
            // enough to be theoretical — the service fee alone makes a total
            // positive — but "adjust a hold that does not exist" has to mean
            // taking one rather than silently leaving an order unpaid.
            hold(order, memo);
            return;
        }
        int delta = order.getTotalCents() - previousTotalCents;
        if (delta == 0) return;
        WalletApi.Reference reference =
            WalletApi.Reference.of(REF_KIND, order.getId(), "Order changed");
        if (delta > 0) {
            wallet.hold(OwnerKind.USER, order.getUserId(), delta, reference,
                key(order, "hold:r" + order.getRevision()));
        } else {
            wallet.release(OwnerKind.USER, order.getUserId(), -delta, reference,
                key(order, "release:r" + order.getRevision()));
        }
    }

    /**
     * Splits what is left of the hold at delivery: each surviving merchant
     * their base minus commission, the platform every commission plus the
     * service fee, the courier every delivery fee and the tip. Idempotent on
     * the order, so passing through DELIVERED twice cannot pay anybody twice.
     *
     * @param merchantNames display names per merchant id, for the statement
     */
    void settle(CustomerOrder order, Map<UUID, String> merchantNames) {
        if (order.getPaymentStatus() != PaymentStatus.HELD) return;

        List<WalletApi.Split> splits = new ArrayList<>();
        long platformTake = order.getServiceFeeCents();
        int courierFees = 0;
        for (SubOrder sub : order.getSubOrders()) {
            if (sub.getStatus() == SubOrderStatus.CANCELLED) continue;
            int merchantBase = sub.getSubtotalCents() - sub.getDiscountCents();
            long commission = fees.platformFee(FeeApi.DELIVERY, merchantBase);
            platformTake += commission;
            courierFees += sub.getDeliveryFeeCents();
            splits.add(new WalletApi.Split(
                AccountRef.merchant(sub.getMerchantId(), Bucket.AVAILABLE),
                merchantBase - commission, LedgerKind.CAPTURE,
                merchantNames.getOrDefault(sub.getMerchantId(), "Restaurant")));
        }
        splits.add(new WalletApi.Split(AccountRef.platform(), platformTake,
            LedgerKind.FEE, "Service + commission"));
        // The courier's two lines, now that there is a courier.
        AccountRef courier = courierAccount(order);
        splits.add(new WalletApi.Split(courier, courierFees,
            LedgerKind.COURIER_FEE, "Delivery"));
        splits.add(new WalletApi.Split(courier, order.getTipCents(),
            LedgerKind.TIP, "Tip"));

        long sum = splits.stream().mapToLong(WalletApi.Split::amountMinor).sum();
        if (sum != order.heldRemainingCents()) {
            // Impossible unless the arithmetic in Basket, the per-slice releases
            // and the arithmetic here have drifted. Refusing beats stranding the
            // difference in escrow where nobody would notice it for a month.
            log.error("Order {} splits sum to {} but {} remains held — not settling",
                order.getId(), sum, order.heldRemainingCents());
            return;
        }

        wallet.capture(OwnerKind.USER, order.getUserId(), splits,
            WalletApi.Reference.of(REF_KIND, order.getId(), memoFor(order, merchantNames)),
            key(order, "capture"));
        order.settled(OffsetDateTime.now());
    }

    /**
     * One slice's share goes back — its merchant rejected it, never answered,
     * or the customer changed their mind about that kitchen before it started.
     *
     * <p>The key carries the sub-order id, so releasing two different slices is
     * two movements while a retried release of one is one. The running total on
     * the parent is what keeps the final settlement honest.
     */
    void releaseSubOrder(CustomerOrder order, SubOrder sub, String merchantName) {
        int share = sub.shareCents();
        if (order.getPaymentStatus() != PaymentStatus.HELD || share <= 0) return;
        wallet.release(OwnerKind.USER, order.getUserId(), share,
            WalletApi.Reference.of(REF_KIND, order.getId(), merchantName),
            key(order, "release:" + sub.getId()));
        order.partiallyReleased(share);
    }

    /** Gives back whatever the hold still covers. The order ended before the
     *  courier moved — including the case where its last live slice just did. */
    void release(CustomerOrder order) {
        if (order.getPaymentStatus() != PaymentStatus.HELD) return;
        int remaining = order.heldRemainingCents();
        if (remaining > 0) {
            wallet.release(OwnerKind.USER, order.getUserId(), remaining,
                WalletApi.Reference.of(REF_KIND, order.getId(), "Order cancelled"),
                key(order, "release"));
        }
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
     * Who the delivery fees and the tip belong to.
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

    /** What the merchant actually earned on their slice, for their dashboard. */
    long merchantEarningsOn(SubOrder sub) {
        int base = sub.getSubtotalCents() - sub.getDiscountCents();
        return base - fees.platformFee(FeeApi.DELIVERY, base);
    }

    private static String memoFor(CustomerOrder order, Map<UUID, String> merchantNames) {
        return order.getSubOrders().stream()
            .filter(s -> s.getStatus() != SubOrderStatus.CANCELLED)
            .map(s -> merchantNames.getOrDefault(s.getMerchantId(), "Restaurant"))
            .distinct()
            .reduce((a, b) -> a + ", " + b)
            .orElse("Order");
    }

    private static String key(CustomerOrder order, String verb) {
        return "order:" + order.getId() + ":" + verb;
    }
}
