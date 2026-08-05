package com.gojogo.services.internal;

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
 * The services vertical's whole relationship with money — the
 * {@code OrderPayments} shape, third vertical.
 *
 * <pre>
 *   request / quote-accept   AVAILABLE ─── price ──▶ ESCROW
 *   settled (post-window)    ESCROW ─── price − commission ──▶ provider
 *                            ESCROW ─── commission ──▶ platform
 *   declined / free cancel   ESCROW ─── price ──▶ AVAILABLE
 *   late cancel / no-show    ESCROW ─── remainder ──▶ AVAILABLE   (fee stays)
 *                            ESCROW ─── fee − commission ──▶ provider
 *                            ESCROW ─── commission on fee ──▶ platform
 * </pre>
 *
 * <p>Commission is {@code FeeApi.SERVICES} on whatever the provider is
 * actually paid — the full price on completed work, the fee on a late
 * cancellation. The invariant is the standing one: splits plus releases equal
 * the hold, or nothing moves.
 */
@Service
class BookingPayments {

    private static final Logger log = LoggerFactory.getLogger(BookingPayments.class);

    private static final String REQUIRED_KEY = "services.booking.wallet.required";
    private static final String REF_KIND = "BOOKING";

    private final WalletApi wallet;
    private final FeeApi fees;
    private final ConfigApi config;

    BookingPayments(WalletApi wallet, FeeApi fees, ConfigApi config) {
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

    void hold(Booking booking, String memo) {
        if (booking.getPriceCents() == null) return;
        if (!required() || booking.getPriceCents() <= 0) {
            booking.held();
            return;
        }
        wallet.hold(OwnerKind.USER, booking.getCustomerId(), booking.getPriceCents(),
            WalletApi.Reference.of(REF_KIND, booking.getId(), memo),
            key(booking, "hold"));
        booking.held();
    }

    void release(Booking booking, String memo) {
        if (booking.getPaymentStatus() != BookingPaymentState.HELD) return;
        if (required() && booking.getPriceCents() != null && booking.getPriceCents() > 0) {
            wallet.release(OwnerKind.USER, booking.getCustomerId(), booking.getPriceCents(),
                WalletApi.Reference.of(REF_KIND, booking.getId(), memo),
                key(booking, "release"));
        }
        booking.releasedFunds(OffsetDateTime.now());
    }

    /** The full settlement — completed work whose capture window has passed,
     *  or a no-show, which SPECS prices at 100%. */
    void settle(Booking booking, UUID providerId, String providerName) {
        if (booking.getPaymentStatus() != BookingPaymentState.HELD) return;
        if (!required() || booking.getPriceCents() == null || booking.getPriceCents() <= 0) {
            booking.settled(OffsetDateTime.now());
            return;
        }
        capture(booking, providerId, providerName, booking.getPriceCents(), 0);
        booking.settled(OffsetDateTime.now());
    }

    /**
     * A late cancellation: the fee is captured for the provider (less
     * commission), the remainder goes back to the customer — one release and
     * one capture, which together account for the hold to the cent.
     */
    void settleCancellationFee(Booking booking, UUID providerId, String providerName,
                               long feeCents) {
        if (booking.getPaymentStatus() != BookingPaymentState.HELD) return;
        if (!required() || booking.getPriceCents() == null || booking.getPriceCents() <= 0) {
            booking.releasedFunds(OffsetDateTime.now());
            return;
        }
        long price = booking.getPriceCents();
        long fee = Math.clamp(feeCents, 0, price);
        if (fee == 0) {
            release(booking, "Booking cancelled");
            return;
        }
        long remainder = price - fee;
        if (remainder > 0) {
            wallet.release(OwnerKind.USER, booking.getCustomerId(), remainder,
                WalletApi.Reference.of(REF_KIND, booking.getId(), "Booking cancelled"),
                key(booking, "release-remainder"));
        }
        capture(booking, providerId, providerName, fee, remainder);
        booking.settled(OffsetDateTime.now());
    }

    private void capture(Booking booking, UUID providerId, String providerName,
                         long amount, long alreadyReleased) {
        long commission = fees.platformFee(FeeApi.SERVICES, amount);
        List<WalletApi.Split> splits = List.of(
            new WalletApi.Split(AccountRef.merchant(providerId, Bucket.AVAILABLE),
                amount - commission, LedgerKind.CAPTURE, providerName),
            new WalletApi.Split(AccountRef.platform(), commission, LedgerKind.FEE, "Commission"));
        long sum = splits.stream().mapToLong(WalletApi.Split::amountMinor).sum();
        if (sum + alreadyReleased != booking.getPriceCents()) {
            log.error("Booking {} splits {} + released {} != held {} — not settling",
                booking.getId(), sum, alreadyReleased, booking.getPriceCents());
            return;
        }
        wallet.capture(OwnerKind.USER, booking.getCustomerId(), splits,
            WalletApi.Reference.of(REF_KIND, booking.getId(), providerName),
            key(booking, "capture"));
    }

    private static String key(Booking booking, String verb) {
        return "booking:" + booking.getId() + ":" + verb;
    }
}
