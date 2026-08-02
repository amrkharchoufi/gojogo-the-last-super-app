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
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Where the delivery fee and the tip end up — the one line Phase 4 M1 was
 * designed, two milestones ago, to be.
 *
 * <p>2e M3 could have folded both into commission and settled the lot to the
 * platform. It deliberately did not: they went to the platform under
 * {@code COURIER_FEE} and {@code TIP}, their own ledger kinds, so that the day
 * couriers existed the change would be a payee rather than an archaeology
 * project across a year of platform revenue. This is the test that the payee
 * actually moved, and that it moved on both paths — the split at delivery, and
 * a tip added afterwards.
 */
class CourierPayTests {

    private static final UUID CUSTOMER = UUID.randomUUID();
    private static final UUID MERCHANT = UUID.randomUUID();
    private static final UUID COURIER = UUID.randomUUID();

    private WalletApi wallet;
    private OrderPayments payments;
    private CustomerOrder order;

    @BeforeEach
    void setUp() {
        wallet = mock(WalletApi.class);
        FeeApi fees = mock(FeeApi.class);
        ConfigApi config = mock(ConfigApi.class);
        when(config.flag(anyString(), org.mockito.ArgumentMatchers.anyBoolean())).thenReturn(true);
        // 20% of the food, which is what the real registry is seeded with.
        when(fees.platformFee(anyString(), anyLong())).thenAnswer(call ->
            Math.round(((Number) call.getArgument(1)).longValue() * 0.20));
        payments = new OrderPayments(wallet, fees, config);

        order = new CustomerOrder(CUSTOMER, MERCHANT, "USD", "", OffsetDateTime.now());
        set(order, "id", UUID.randomUUID());
        order.priceIt(Basket.of(2_000, 300, 99, 0, 250, "USD"), null, null);
        order.held(OffsetDateTime.now());
    }

    @Test
    @DisplayName("the delivery fee and the tip go to the courier who carried it")
    void settlementPaysTheCourier() {
        order.assignCourier(UUID.randomUUID(), COURIER, "Yassine B.", "E-bike", null, 0);

        payments.settle(order, "Forno Nero");

        AccountRef courierAccount = AccountRef.user(COURIER, Bucket.AVAILABLE);
        assertThat(splits())
            .filteredOn(s -> s.kind() == LedgerKind.COURIER_FEE || s.kind() == LedgerKind.TIP)
            .isNotEmpty()
            .allMatch(s -> s.payee().equals(courierAccount));
        assertThat(splits())
            .filteredOn(s -> s.kind() == LedgerKind.COURIER_FEE)
            .singleElement()
            .extracting(WalletApi.Split::amountMinor)
            .isEqualTo(300L);
        assertThat(splits())
            .filteredOn(s -> s.kind() == LedgerKind.TIP)
            .singleElement()
            .extracting(WalletApi.Split::amountMinor)
            .isEqualTo(250L);
    }

    /** The merchant's and the platform's shares are unchanged by any of this —
     *  a courier is paid out of the fee the customer already paid, not out of
     *  somebody else's cut. */
    @Test
    void nobodyElsesShareMoved() {
        order.assignCourier(UUID.randomUUID(), COURIER, "Yassine B.", "E-bike", null, 0);

        payments.settle(order, "Forno Nero");

        assertThat(splits())
            .filteredOn(s -> s.payee().ownerKind() == OwnerKind.MERCHANT)
            .singleElement()
            .extracting(WalletApi.Split::amountMinor)
            .isEqualTo(1_600L);                       // 2000 food − 20% commission
        assertThat(splits())
            .filteredOn(s -> s.payee().ownerKind() == OwnerKind.PLATFORM)
            .singleElement()
            .extracting(WalletApi.Split::amountMinor)
            .isEqualTo(499L);                         // 400 commission + 99 service fee
    }

    /**
     * Every order delivered before this milestone had no courier. Not a soft
     * failure mode: a split has to name an account, and refusing to settle an
     * old order would strand its money in escrow rather than surface anything.
     */
    @Test
    void anOrderWithNoCourierStillSettlesToThePlatform() {
        payments.settle(order, "Forno Nero");

        assertThat(splits())
            .filteredOn(s -> s.kind() == LedgerKind.COURIER_FEE || s.kind() == LedgerKind.TIP)
            .isNotEmpty()
            .allMatch(s -> s.payee().ownerKind() == OwnerKind.PLATFORM);
    }

    /** The invariant that makes the whole thing safe: if the payees ever stopped
     *  adding up to the hold, {@code settle} refuses rather than stranding the
     *  difference in escrow where nobody would notice it for a month. */
    @Test
    void theSplitsStillSumToWhatWasHeld() {
        order.assignCourier(UUID.randomUUID(), COURIER, "Yassine B.", "E-bike", null, 0);

        payments.settle(order, "Forno Nero");

        assertThat(splits().stream().mapToLong(WalletApi.Split::amountMinor).sum())
            .isEqualTo(order.getTotalCents());
    }

    @Test
    @DisplayName("a tip added after delivery reaches the courier too")
    void aLateTipGoesToTheCourier() {
        order.assignCourier(UUID.randomUUID(), COURIER, "Yassine B.", "E-bike", null, 0);
        order.settled(OffsetDateTime.now());

        payments.tipAfterDelivery(order, 500);

        ArgumentCaptor<AccountRef> to = ArgumentCaptor.forClass(AccountRef.class);
        verify(wallet).transfer(any(), to.capture(), anyLong(), any(), any(), anyString());
        assertThat(to.getValue()).isEqualTo(AccountRef.user(COURIER, Bucket.AVAILABLE));
        assertThat(order.getTipCents()).isEqualTo(750);   // 250 up front + 500 after
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
