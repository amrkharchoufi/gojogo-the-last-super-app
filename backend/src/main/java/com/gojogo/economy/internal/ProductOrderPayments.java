package com.gojogo.economy.internal;

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
import java.util.List;
import java.util.UUID;

/**
 * Economy's whole relationship with money — the {@code OrderPayments} shape,
 * one vertical over.
 *
 * <pre>
 *   placement   AVAILABLE ─── total ──▶ ESCROW      (the buyer's, still)
 *   completed   ESCROW ─── total − commission ──▶ seller
 *               ESCROW ─── commission ──▶ platform
 *   cancelled   ESCROW ─── total ──▶ AVAILABLE
 * </pre>
 *
 * <p>The invariant is delivery's, without the courier: the splits must equal
 * the hold to the cent or nothing settles. Commission ({@code FeeApi.ECONOMY})
 * is charged on the discounted goods value only — never on shipping or tax,
 * which the seller collects at cost.
 */
@Service
class ProductOrderPayments {

    private static final Logger log = LoggerFactory.getLogger(ProductOrderPayments.class);

    /** Same posture as {@code delivery.checkout.wallet.required}: real
     *  environments pay; an environment with no funding path can still
     *  exercise the vertical. */
    private static final String REQUIRED_KEY = "economy.checkout.wallet.required";
    private static final String REF_KIND = "PRODUCT_ORDER";

    private final WalletApi wallet;
    private final FeeApi fees;
    private final ConfigApi config;

    ProductOrderPayments(WalletApi wallet, FeeApi fees, ConfigApi config) {
        this.wallet = wallet;
        this.fees = fees;
        this.config = config;
    }

    boolean required() {
        return config.flag(REQUIRED_KEY, true);
    }

    String currency() {
        return wallet.currency();
    }

    void hold(ProductOrder order, String memo) {
        if (!required() || order.getTotalCents() <= 0) return;
        wallet.hold(OwnerKind.USER, order.getBuyerId(), order.getTotalCents(),
            WalletApi.Reference.of(REF_KIND, order.getId(), memo),
            key(order, "hold"));
        order.held(OffsetDateTime.now());
    }

    void settle(ProductOrder order, String sellerName) {
        if (order.getPaymentStatus() != ProductOrder.PaymentState.HELD) return;
        int base = order.getSubtotalCents() - order.getDiscountCents();
        long commission = fees.platformFee(FeeApi.ECONOMY, base);
        List<WalletApi.Split> splits = List.of(
            new WalletApi.Split(AccountRef.merchant(order.getSellerId(), Bucket.AVAILABLE),
                order.getTotalCents() - commission, LedgerKind.CAPTURE, sellerName),
            new WalletApi.Split(AccountRef.platform(), commission,
                LedgerKind.FEE, "Commission"));
        long sum = splits.stream().mapToLong(WalletApi.Split::amountMinor).sum();
        if (sum != order.getTotalCents()) {
            log.error("Product order {} splits sum to {} but {} is held — not settling",
                order.getId(), sum, order.getTotalCents());
            return;
        }
        wallet.capture(OwnerKind.USER, order.getBuyerId(), splits,
            WalletApi.Reference.of(REF_KIND, order.getId(), sellerName),
            key(order, "capture"));
        order.settled(OffsetDateTime.now());
    }

    void release(ProductOrder order) {
        if (order.getPaymentStatus() != ProductOrder.PaymentState.HELD) return;
        if (order.getTotalCents() > 0) {
            wallet.release(OwnerKind.USER, order.getBuyerId(), order.getTotalCents(),
                WalletApi.Reference.of(REF_KIND, order.getId(), "Order cancelled"),
                key(order, "release"));
        }
        order.releasedFunds(OffsetDateTime.now());
    }

    private static String key(ProductOrder order, String verb) {
        return "product-order:" + order.getId() + ":" + verb;
    }

    // MARK: Ownership transfers (Phase 5 M2)

    private static final String TRANSFER_REF = "TRANSFER";

    /** What the wallet may be asked to escrow for one transfer. Above it, the
     *  transfer is flagged for manual settlement (SPECS §6). */
    long transferWalletCapCents() {
        return Math.max(0, config.number("economy.transfer.wallet.cap.cents", 1_000_000));
    }

    void holdTransfer(OwnershipTransfer transfer, String memo) {
        if (!required()) {
            transfer.paid(OffsetDateTime.now());
            return;
        }
        wallet.hold(OwnerKind.USER, transfer.getBuyerId(), transfer.getPriceCents(),
            WalletApi.Reference.of(TRANSFER_REF, transfer.getId(), memo),
            transferKey(transfer, "hold"));
        transfer.paid(OffsetDateTime.now());
    }

    void releaseTransfer(OwnershipTransfer transfer) {
        if (!required() || transfer.getState() != TransferState.PAYMENT_HELD) return;
        wallet.release(OwnerKind.USER, transfer.getBuyerId(), transfer.getPriceCents(),
            WalletApi.Reference.of(TRANSFER_REF, transfer.getId(), "Transfer cancelled"),
            transferKey(transfer, "release"));
    }

    /**
     * The handover settled: the seller — a person, not a merchant account —
     * gets the price less commission, the platform the commission. The same
     * invariant as every settlement: splits equal the hold or nothing moves.
     */
    void settleTransfer(OwnershipTransfer transfer, String memo) {
        if (!required()) return;
        long price = transfer.getPriceCents();
        long commission = fees.platformFee(FeeApi.ECONOMY, price);
        List<WalletApi.Split> splits = List.of(
            new WalletApi.Split(AccountRef.user(transfer.getSellerId(), Bucket.AVAILABLE),
                price - commission, LedgerKind.CAPTURE, memo),
            new WalletApi.Split(AccountRef.platform(), commission,
                LedgerKind.FEE, "Commission"));
        wallet.capture(OwnerKind.USER, transfer.getBuyerId(), splits,
            WalletApi.Reference.of(TRANSFER_REF, transfer.getId(), memo),
            transferKey(transfer, "capture"));
    }

    private static String transferKey(OwnershipTransfer transfer, String verb) {
        return "transfer:" + transfer.getId() + ":" + verb;
    }
}
