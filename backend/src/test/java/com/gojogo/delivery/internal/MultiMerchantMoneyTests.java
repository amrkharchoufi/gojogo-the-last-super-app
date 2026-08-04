package com.gojogo.delivery.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.payments.AccountRef;
import com.gojogo.payments.Bucket;
import com.gojogo.payments.FeeApi;
import com.gojogo.payments.LedgerKind;
import com.gojogo.payments.OwnerKind;
import com.gojogo.payments.WalletApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.lang.reflect.Field;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The money on an order that spans kitchens (Phase 4 M3). The invariant under
 * test is the settlement's second term: what the splits pay out plus what
 * per-slice cancellations already released must equal the hold, to the cent —
 * and when it doesn't, nothing settles, because stranding a difference in
 * escrow is the failure nobody notices for a month.
 */
class MultiMerchantMoneyTests {

    private static final UUID CUSTOMER = UUID.randomUUID();
    private static final UUID FORNO = UUID.randomUUID();
    private static final UUID SUSHI = UUID.randomUUID();
    private static final UUID COURIER = UUID.randomUUID();

    private WalletApi wallet;
    private OrderPayments payments;
    private CustomerOrder order;
    private SubOrder fornoSlice;
    private SubOrder sushiSlice;

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
        fornoSlice = order.addSubOrder(FORNO, 2_000, 300, 0, null, "");
        set(fornoSlice, "id", UUID.randomUUID());
        sushiSlice = order.addSubOrder(SUSHI, 3_000, 400, 500, null, "SAVE5");
        set(sushiSlice, "id", UUID.randomUUID());
        order.priceIt(Basket.of(List.of(
                Basket.MerchantSlice.of(FORNO, 2_000, 300, 0, null, "", ""),
                Basket.MerchantSlice.of(SUSHI, 3_000, 400, 500, null, "SAVE5", "Save $5")),
            99, 250, "USD"));
        order.held(OffsetDateTime.now());
        order.assignCourier(UUID.randomUUID(), COURIER, "Yassine B.", "E-bike", null, 0);
    }

    @Test
    @DisplayName("each kitchen is paid their own base minus their own commission")
    void everyKitchenIsPaidTheirOwnSlice() {
        payments.settle(order, names());

        assertThat(splits())
            .filteredOn(s -> s.payee().equals(AccountRef.merchant(FORNO, Bucket.AVAILABLE)))
            .singleElement()
            .extracting(WalletApi.Split::amountMinor)
            .isEqualTo(1_600L);                        // 2000 − 20%
        assertThat(splits())
            .filteredOn(s -> s.payee().equals(AccountRef.merchant(SUSHI, Bucket.AVAILABLE)))
            .singleElement()
            .extracting(WalletApi.Split::amountMinor)
            .isEqualTo(2_000L);                        // (3000 − 500) − 20%
    }

    /** The courier makes every stop and is paid every stop's fee. */
    @Test
    void theCourierIsPaidEveryStopsFee() {
        payments.settle(order, names());

        assertThat(splits())
            .filteredOn(s -> s.kind() == LedgerKind.COURIER_FEE)
            .singleElement()
            .extracting(WalletApi.Split::amountMinor)
            .isEqualTo(700L);                          // 300 + 400
        assertThat(splits().stream().mapToLong(WalletApi.Split::amountMinor).sum())
            .isEqualTo(order.getTotalCents());
    }

    @Test
    @DisplayName("a released slice moves exactly its share and shrinks what settlement must account for")
    void aReleasedSliceShrinksTheHold() {
        payments.releaseSubOrder(order, sushiSlice, "Kaido Sushi");
        sushiSlice.cancelledBecause("Out of rice");

        // subtotal 3000 − discount 500 + fee 400 = 2900, and nothing else.
        verify(wallet).release(eq(OwnerKind.USER), eq(CUSTOMER), eq(2_900L),
            any(), anyString());
        assertThat(order.getReleasedCents()).isEqualTo(2_900);

        payments.settle(order, names());

        // The surviving splits sum to exactly what remains held.
        assertThat(splits().stream().mapToLong(WalletApi.Split::amountMinor).sum())
            .isEqualTo(order.getTotalCents() - 2_900);
        assertThat(splits())
            .noneMatch(s -> s.payee().equals(AccountRef.merchant(SUSHI, Bucket.AVAILABLE)));
    }

    /** The refusal that guards the ledger: if the arithmetic ever drifts, the
     *  money stays in escrow and the log screams, rather than a silent
     *  short-pay. */
    @Test
    void aDriftedSumRefusesToSettle() {
        order.partiallyReleased(1);   // now nothing can sum to the remainder

        payments.settle(order, names());

        verify(wallet, never()).capture(any(), any(), any(), any(), anyString());
        assertThat(order.getPaymentStatus()).isEqualTo(PaymentStatus.HELD);
    }

    /** The full release after per-slice releases gives back only what is left —
     *  releasing the full total again would mint money. */
    @Test
    void theFinalReleaseCoversOnlyWhatRemains() {
        payments.releaseSubOrder(order, sushiSlice, "Kaido Sushi");
        sushiSlice.cancelledBecause("Out of rice");

        payments.release(order);

        verify(wallet).release(eq(OwnerKind.USER), eq(CUSTOMER),
            eq((long) order.getTotalCents() - 2_900), any(), anyString());
    }

    private Map<UUID, String> names() {
        return Map.of(FORNO, "Forno Nero", SUSHI, "Kaido Sushi");
    }

    @SuppressWarnings("unchecked")
    private List<WalletApi.Split> splits() {
        ArgumentCaptor<List<WalletApi.Split>> captor = ArgumentCaptor.forClass(List.class);
        verify(wallet).capture(any(), any(), captor.capture(), any(), anyString());
        return captor.getValue();
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
