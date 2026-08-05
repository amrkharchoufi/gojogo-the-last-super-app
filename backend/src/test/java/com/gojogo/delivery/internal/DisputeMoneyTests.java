package com.gojogo.delivery.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.payments.AccountRef;
import com.gojogo.payments.Bucket;
import com.gojogo.payments.FeeApi;
import com.gojogo.payments.OwnerKind;
import com.gojogo.payments.WalletApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.lang.reflect.Field;
import java.time.OffsetDateTime;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * What each party actually received for an order, and where a refund comes from
 * (Phase 4 M6).
 *
 * <p>This is the arithmetic a dispute refusal is argued from, so it gets its own
 * tests rather than riding on the service's. The invariant being pinned is that
 * the three ceilings are exactly the three splits settlement made — if they ever
 * drift, an operator refunds against a number the ledger will not honour.
 */
class DisputeMoneyTests {

    private static final UUID CUSTOMER = UUID.randomUUID();
    private static final UUID MERCHANT = UUID.randomUUID();
    private static final UUID COURIER = UUID.randomUUID();

    private WalletApi wallet;
    private OrderPayments payments;
    private CustomerOrder order;
    private SubOrder slice;

    @BeforeEach
    void setUp() {
        wallet = mock(WalletApi.class);
        FeeApi fees = mock(FeeApi.class);
        ConfigApi config = mock(ConfigApi.class);
        when(config.flag(anyString(), anyBoolean())).thenReturn(true);
        // 20% of the food, which is what the real registry is seeded with.
        when(fees.platformFee(anyString(), anyLong())).thenAnswer(call ->
            Math.round(((Number) call.getArgument(1)).longValue() * 0.20));
        payments = new OrderPayments(wallet, fees, config);

        order = new CustomerOrder(CUSTOMER, "USD", "", OffsetDateTime.now());
        set(order, "id", UUID.randomUUID());
        slice = order.addSubOrder(MERCHANT, 2_000, 300, 0, null, "");
        set(slice, "id", UUID.randomUUID());
        order.priceIt(Basket.of(MERCHANT, 2_000, 300, 99, 0, 250, "USD"));
        order.assignCourier(UUID.randomUUID(), COURIER, "Yassine B.", "Bike",
            java.math.BigDecimal.valueOf(4.9), 210);
        order.held(OffsetDateTime.now());
    }

    // MARK: The three ceilings

    /**
     * The ceilings are the splits. Food 2000, commission 400, so the kitchen
     * kept 1600; the courier got the 300 fee plus the 250 tip; the platform got
     * the 400 commission plus the 99 service fee. Those three sum to the total,
     * which is the point — a refund can never exceed what the order generated.
     */
    @Test
    @DisplayName("each party's ceiling is exactly what settlement paid them")
    void theCeilingsAreTheSplits() {
        long merchant = payments.receivedOnOrder(order, DisputePayer.MERCHANT, slice);
        long courier = payments.receivedOnOrder(order, DisputePayer.COURIER, slice);
        long platform = payments.receivedOnOrder(order, DisputePayer.PLATFORM, slice);

        assertThat(merchant).isEqualTo(1_600);
        assertThat(courier).isEqualTo(550);
        assertThat(platform).isEqualTo(499);
        assertThat(merchant + courier + platform).isEqualTo(order.getTotalCents());
    }

    /** "The merchant pays" means nothing without a kitchen named, so there is
     *  nothing it could be capped at. */
    @Test
    void aMerchantCeilingWithNoSliceIsZero() {
        assertThat(payments.receivedOnOrder(order, DisputePayer.MERCHANT, null)).isZero();
    }

    @Test
    @DisplayName("a cancelled slice was never paid, so it cannot fund a refund")
    void aCancelledSliceHasNoCeiling() {
        slice.cancelledBecause("The restaurant couldn't take this order");

        assertThat(payments.receivedOnOrder(order, DisputePayer.MERCHANT, slice)).isZero();
        // And it stops counting toward the platform's commission too, exactly
        // as settlement skips it.
        assertThat(payments.receivedOnOrder(order, DisputePayer.PLATFORM, slice))
            .isEqualTo(order.getServiceFeeCents());
    }

    /** Nobody carried it, so there is nobody to take it back off. */
    @Test
    void aCollectionHasNoCourierCeiling() {
        order.fulfilBy(FulfilmentKind.PICKUP);

        assertThat(payments.receivedOnOrder(order, DisputePayer.COURIER, slice)).isZero();
    }

    // MARK: The refund itself

    @Test
    @DisplayName("a refund is a reversal off the named party, into the customer's own balance")
    void aRefundMovesFromThePayerToTheCustomer() {
        UUID disputeId = UUID.randomUUID();

        payments.refundDispute(order, disputeId, DisputePayer.MERCHANT, slice, 600);

        ArgumentCaptor<AccountRef> from = ArgumentCaptor.forClass(AccountRef.class);
        ArgumentCaptor<AccountRef> to = ArgumentCaptor.forClass(AccountRef.class);
        ArgumentCaptor<String> key = ArgumentCaptor.forClass(String.class);
        verify(wallet).refund(from.capture(), to.capture(), eq(600L), any(), key.capture());
        assertThat(from.getValue()).isEqualTo(AccountRef.merchant(MERCHANT, Bucket.AVAILABLE));
        assertThat(to.getValue()).isEqualTo(AccountRef.user(CUSTOMER, Bucket.AVAILABLE));
        // Keyed on the dispute rather than the order, so a retried resolution is
        // one movement.
        assertThat(key.getValue()).contains(disputeId.toString());
    }

    @Test
    void aCourierRefundComesOffTheCourier() {
        payments.refundDispute(order, UUID.randomUUID(), DisputePayer.COURIER, null, 550);

        ArgumentCaptor<AccountRef> from = ArgumentCaptor.forClass(AccountRef.class);
        verify(wallet).refund(from.capture(), any(), eq(550L), any(), anyString());
        assertThat(from.getValue()).isEqualTo(AccountRef.user(COURIER, Bucket.AVAILABLE));
    }

    /**
     * The question a merchant ceiling cannot answer: a kitchen paid on Tuesday
     * and withdrawn on Wednesday received the money and cannot return it. Only
     * EXTERNAL accounts may go negative, so asking first is what turns a ledger
     * exception into a sentence an operator can act on.
     */
    @Test
    @DisplayName("what a payer can cover is a different question from what they were paid")
    void theBalanceIsAskedSeparatelyFromTheCeiling() {
        when(wallet.balancesOf(eq(OwnerKind.MERCHANT), eq(MERCHANT)))
            .thenReturn(new WalletApi.Balances("USD", 120, 0, 0, 0, 0));

        assertThat(payments.receivedOnOrder(order, DisputePayer.MERCHANT, slice)).isEqualTo(1_600);
        assertThat(payments.availableForPayer(order, DisputePayer.MERCHANT, slice)).isEqualTo(120);
    }

    private static void set(Object target, String field, Object value) {
        try {
            Field f = target.getClass().getDeclaredField(field);
            f.setAccessible(true);
            f.set(target, value);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(e);
        }
    }
}
