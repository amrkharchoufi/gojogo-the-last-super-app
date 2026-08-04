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
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The money on a collection (Phase 4 M4).
 *
 * <p>The claim being tested is that settlement did not have to learn anything:
 * a pickup is the arithmetic §1 already does with the courier's two lines at
 * zero, and the ledger drops a zero split because a zero fee is not an entry.
 * If that is true, the split is food − commission to the kitchen and commission
 * + service fee to the platform, and nothing at all under COURIER_FEE or TIP.
 */
class PickupMoneyTests {

    private static final UUID CUSTOMER = UUID.randomUUID();
    private static final UUID FORNO = UUID.randomUUID();

    private WalletApi wallet;
    private OrderPayments payments;
    private CustomerOrder order;

    @BeforeEach
    void setUp() {
        wallet = mock(WalletApi.class);
        FeeApi fees = mock(FeeApi.class);
        ConfigApi config = mock(ConfigApi.class);
        when(config.flag(anyString(), anyBoolean())).thenReturn(true);
        when(fees.platformFee(anyString(), anyLong())).thenAnswer(call ->
            Math.round(((Number) call.getArgument(1)).longValue() * 0.20));
        payments = new OrderPayments(wallet, fees, config);

        order = new CustomerOrder(CUSTOMER, "USD", "", OffsetDateTime.now());
        set(order, "id", UUID.randomUUID());
        order.fulfilBy(FulfilmentKind.PICKUP);
        SubOrder slice = order.addSubOrder(FORNO, 2_000, 0, 0, null, "");
        set(slice, "id", UUID.randomUUID());
        order.priceIt(Basket.of(
            List.of(Basket.MerchantSlice.of(FORNO, 2_000, 0, 0, null, "", "")),
            99, 0, "USD"));
        order.held(OffsetDateTime.now());
    }

    @Test
    @DisplayName("a collection pays the kitchen and the platform, and nobody else")
    void thereIsNoCourierToPay() {
        payments.settle(order, Map.of(FORNO, "Forno Nero"));

        assertThat(splits())
            .filteredOn(s -> s.payee().equals(AccountRef.merchant(FORNO, Bucket.AVAILABLE)))
            .singleElement()
            .extracting(WalletApi.Split::amountMinor)
            .isEqualTo(1_600L);                      // 2000 − 20%
        assertThat(splits())
            .filteredOn(s -> s.kind() == LedgerKind.FEE)
            .singleElement()
            .extracting(WalletApi.Split::amountMinor)
            .isEqualTo(499L);                        // 400 commission + 99 service fee
        // The two courier lines are still constructed — settle has one shape —
        // and they are worth nothing, which is what the ledger drops.
        assertThat(splits())
            .filteredOn(s -> s.kind() == LedgerKind.COURIER_FEE || s.kind() == LedgerKind.TIP)
            .allMatch(s -> s.amountMinor() == 0);
    }

    /** The same invariant as every other order: what is split equals what is
     *  held, to the cent, or nothing settles. */
    @Test
    void theSplitsStillSumToTheHold() {
        payments.settle(order, Map.of(FORNO, "Forno Nero"));

        assertThat(splits().stream().mapToLong(WalletApi.Split::amountMinor).sum())
            .isEqualTo(order.getTotalCents())
            .isEqualTo(2_099L);
        assertThat(order.getPaymentStatus()).isEqualTo(PaymentStatus.CAPTURED);
    }

    @SuppressWarnings("unchecked")
    private List<WalletApi.Split> splits() {
        ArgumentCaptor<List<WalletApi.Split>> captor = ArgumentCaptor.forClass(List.class);
        verify(wallet).capture(eq(OwnerKind.USER), eq(CUSTOMER), captor.capture(),
            any(), anyString());
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
