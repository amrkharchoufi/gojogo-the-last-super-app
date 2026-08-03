package com.gojogo.dispatch.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.dispatch.VehicleCategory;
import com.gojogo.dispatch.VehicleRef;
import com.gojogo.dispatch.WorkerKind;
import com.gojogo.payments.LedgerKind;
import com.gojogo.payments.OwnerKind;
import com.gojogo.payments.PayoutApi;
import com.gojogo.payments.WalletApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.web.server.ResponseStatusException;

import java.lang.reflect.Field;
import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * What a worker may take out of their own wallet.
 *
 * <p>Every test here is about one sentence: a worker is paid into the same
 * pocket a card top-up lands in, so a payout surface over that balance is a
 * card→bank pipe unless it is bounded by work actually done. The fixture
 * therefore hands the service a ledger with <em>both</em> kinds of money in it
 * and asserts on which of them can leave.
 */
class WorkerMoneyTests {

    private static final UUID WORKER_USER = UUID.randomUUID();
    private static final UUID STRANGER = UUID.randomUUID();

    private WorkerRepository workers;
    private WalletApi wallet;
    private PayoutApi payouts;
    private WorkerMoneyService money;

    /** What has been credited to this person, by kind — the fixture the
     *  aggregate is answered from. */
    private Map<LedgerKind, Long> credited;
    private long availableMinor;
    private long lifetimePaidOutMinor;

    private Worker courier;

    @BeforeEach
    void setUp() {
        workers = mock(WorkerRepository.class);
        wallet = mock(WalletApi.class);
        payouts = mock(PayoutApi.class);
        ConfigApi config = mock(ConfigApi.class);
        when(config.number(anyString(), anyLong())).thenAnswer(call -> call.getArgument(1));

        credited = new HashMap<>();
        availableMinor = 0;
        lifetimePaidOutMinor = 0;

        courier = worker(WORKER_USER, WorkerKind.COURIER);
        when(workers.findByUserIdOrderByKindAsc(WORKER_USER)).thenReturn(List.of(courier));
        when(workers.findByUserIdOrderByKindAsc(STRANGER)).thenReturn(List.of());

        when(wallet.balancesOf(eq(OwnerKind.USER), any(UUID.class)))
            .thenAnswer(call -> new WalletApi.Balances("USD", availableMinor, 0, 0, 0, 0));
        // The aggregate, answered the way the ledger answers it: the sum of what
        // arrived under the kinds the caller asked for, and nothing else.
        when(wallet.totalByKind(eq(OwnerKind.USER), any(UUID.class), any()))
            .thenAnswer(call -> {
                Set<LedgerKind> kinds = call.getArgument(2);
                return credited.entrySet().stream()
                    .filter(line -> kinds.contains(line.getKey()))
                    .mapToLong(Map.Entry::getValue)
                    .sum();
            });
        when(wallet.statement(eq(OwnerKind.USER), any(UUID.class), anyInt()))
            .thenReturn(List.of());
        when(payouts.lifetimePaidOutMinor(eq(OwnerKind.USER), any(UUID.class)))
            .thenAnswer(call -> lifetimePaidOutMinor);
        when(payouts.statusOf(eq(OwnerKind.USER), any(UUID.class)))
            .thenReturn(new PayoutApi.ConnectStatus(true, "acct_1", true, true, ""));
        when(payouts.payOut(eq(OwnerKind.USER), any(UUID.class), any(UUID.class), anyLong(),
                any(PayoutApi.PayoutGuard.class)))
            .thenAnswer(call -> new PayoutApi.PayoutResult(UUID.randomUUID(),
                call.getArgument(3, Long.class), "USD", "SENT", ""));

        money = new WorkerMoneyService(workers, wallet, payouts, config);
    }

    // MARK: The cap

    @Test
    @DisplayName("withdrawable is what work paid, less what has already been sent out")
    void withdrawableIsEarnedLessPaidOut() {
        earned(LedgerKind.COURIER_FEE, 6_000);
        earned(LedgerKind.TIP, 1_500);
        earned(LedgerKind.RIDE_FARE, 2_500);
        lifetimePaidOutMinor = 4_000;
        availableMinor = 6_000;

        WorkerWalletDto dto = money.wallet(WORKER_USER);

        assertThat(dto.lifetimeEarnedMinor()).isEqualTo(10_000);
        assertThat(dto.withdrawableMinor()).isEqualTo(6_000);
    }

    @Test
    @DisplayName("a card top-up raises the balance and not the ceiling — the whole "
        + "reason the cap exists")
    void aTopUpDoesNotRaiseWhatMayLeave() {
        earned(LedgerKind.COURIER_FEE, 2_000);
        credited.put(LedgerKind.TOPUP, 50_000L);
        availableMinor = 52_000;

        WorkerWalletDto dto = money.wallet(WORKER_USER);

        assertThat(dto.availableMinor()).isEqualTo(52_000);
        assertThat(dto.lifetimeEarnedMinor()).isEqualTo(2_000);
        assertThat(dto.withdrawableMinor()).isEqualTo(2_000);
        // And the money is genuinely stuck: card in, card out is not a thing this
        // endpoint can be talked into.
        assertThatThrownBy(() -> money.payOut(WORKER_USER, 2_100))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("what you've earned working");
        verify(payouts, never()).payOut(any(), any(), any(), anyLong(), any());
    }

    @Test
    @DisplayName("a customer's money passing through does not count as earnings")
    void onlyEarnedKindsCount() {
        credited.put(LedgerKind.CAPTURE, 30_000L);
        credited.put(LedgerKind.RELEASE, 9_000L);
        credited.put(LedgerKind.REFUND, 4_000L);
        earned(LedgerKind.REWARD, 500);
        availableMinor = 43_500;

        assertThat(money.wallet(WORKER_USER).withdrawableMinor()).isEqualTo(500);
    }

    @Test
    @DisplayName("more than the ceiling is a 409 naming the number, not a silent clamp")
    void aboveTheCeilingIsRefusedByName() {
        earned(LedgerKind.COURIER_FEE, 3_000);
        availableMinor = 9_000;

        assertThatThrownBy(() -> money.payOut(WORKER_USER, 3_001))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("30.00");
        // Asking for 50 and watching 30 leave with no explanation is worse than
        // being told no.
        verify(payouts, never()).payOut(any(), any(), any(), anyLong(), any());
    }

    @Test
    @DisplayName("exactly the ceiling goes out")
    void theCeilingItselfIsAllowed() {
        earned(LedgerKind.RIDE_FARE, 3_000);
        availableMinor = 3_000;

        WorkerPayoutDto payout = money.payOut(WORKER_USER, 3_000);

        assertThat(payout.amountMinor()).isEqualTo(3_000);
        assertThat(payout.status()).isEqualTo("SENT");
    }

    @Test
    @DisplayName("the payout carries a guard that re-checks the cap at debit time — so a "
        + "sibling that got there first makes the second request fail under the lock")
    void payoutGuardRechecksTheCapUnderTheLock() {
        earned(LedgerKind.RIDE_FARE, 5_000);
        availableMinor = 5_000;

        // The outer check passes and the payout is delegated, carrying a guard.
        ArgumentCaptor<PayoutApi.PayoutGuard> guard =
            ArgumentCaptor.forClass(PayoutApi.PayoutGuard.class);
        money.payOut(WORKER_USER, 5_000);
        verify(payouts).payOut(eq(OwnerKind.USER), any(), any(), eq(5_000L), guard.capture());

        // Now a concurrent sibling has already withdrawn the lot: paid-out rises
        // to the full earnings and nothing is left to withdraw. Re-running the
        // guard — which is what happens under the balance lock once the sibling
        // commits — must refuse, even though the outer check waved this one on.
        lifetimePaidOutMinor = 5_000;
        assertThatThrownBy(() -> guard.getValue().check())
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("earned");
    }

    @Test
    @DisplayName("earnings already spent cannot be withdrawn twice: the balance caps "
        + "it even when the lifetime total does not")
    void theBalanceIsTheOtherHalfOfTheCeiling() {
        earned(LedgerKind.COURIER_FEE, 8_000);
        availableMinor = 1_200;

        assertThatThrownBy(() -> money.payOut(WORKER_USER, 5_000))
            .isInstanceOf(ResponseStatusException.class)
            // The limit here is the balance, not the rule, so the message must
            // not blame the rule.
            .hasMessageContaining("your whole balance");
    }

    @Test
    @DisplayName("earned it and spent it reads as an empty wallet, not as the cap")
    void anEmptyWalletSaysSo() {
        earned(LedgerKind.COURIER_FEE, 8_000);
        availableMinor = 0;

        // Three facts arrive at the same refusal and only one of them is the
        // rule; blaming the rule for an empty wallet would send somebody looking
        // for earnings they have already spent.
        assertThatThrownBy(() -> money.payOut(WORKER_USER, 1_000))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("already been spent");
    }

    @Test
    @DisplayName("a worker who has earned nothing is told so, rather than shown a number")
    void nothingEarnedYet() {
        availableMinor = 5_000;

        assertThatThrownBy(() -> money.payOut(WORKER_USER, 1_000))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("nothing to withdraw yet");
    }

    @Test
    @DisplayName("withdrawing everything twice is refused the second time — paid-out "
        + "is remembered")
    void paidOutIsNotForgotten() {
        earned(LedgerKind.COURIER_FEE, 5_000);
        availableMinor = 5_000;

        money.payOut(WORKER_USER, 5_000);
        lifetimePaidOutMinor = 5_000;

        assertThatThrownBy(() -> money.payOut(WORKER_USER, 1))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("nothing to withdraw yet");
    }

    @Test
    @DisplayName("having been paid out more than the ledger says was earned floors at "
        + "zero rather than going negative")
    void withdrawableNeverGoesNegative() {
        earned(LedgerKind.TIP, 1_000);
        lifetimePaidOutMinor = 4_000;
        availableMinor = 10_000;

        assertThat(money.wallet(WORKER_USER).withdrawableMinor()).isZero();
    }

    // MARK: Who may ask

    @Test
    @DisplayName("somebody who has never been approved gets a 404, not an empty wallet")
    void aNonWorkerHasNoWalletHere() {
        assertThatThrownBy(() -> money.wallet(STRANGER))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("not registered to drive or deliver");
        assertThatThrownBy(() -> money.payOut(STRANGER, 1_000))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("not registered to drive or deliver");
        assertThatThrownBy(() -> money.onboardingLink(STRANGER, "a@b.c"))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("not registered to drive or deliver");
    }

    @Test
    @DisplayName("a suspended worker can still take out what they already earned")
    void suspensionDoesNotHoldWages() {
        courier.setSuspended(true);
        earned(LedgerKind.COURIER_FEE, 4_000);
        availableMinor = 4_000;

        // They will be offered nothing and can earn nothing more. What they have
        // already earned is theirs, and holding it as leverage over a review is
        // not a thing this platform does.
        assertThat(money.wallet(WORKER_USER).withdrawableMinor()).isEqualTo(4_000);
        assertThat(money.payOut(WORKER_USER, 4_000).status()).isEqualTo("SENT");
    }

    @Test
    @DisplayName("one wallet for a dual-mode person, whichever registration they hold")
    void eitherRegistrationOpensTheSameWallet() {
        Worker driverOnly = worker(STRANGER, WorkerKind.DRIVER);
        when(workers.findByUserIdOrderByKindAsc(STRANGER)).thenReturn(List.of(driverOnly));
        earned(LedgerKind.RIDE_FARE, 2_000);
        availableMinor = 2_000;

        assertThat(money.wallet(STRANGER).withdrawableMinor()).isEqualTo(2_000);
    }

    // MARK: The rest of the payload

    @Test
    @DisplayName("the wallet carries the connect status and the recent lines the "
        + "screen draws")
    void theWalletIsOneRead() {
        earned(LedgerKind.TIP, 700);
        availableMinor = 700;
        when(payouts.statusOf(eq(OwnerKind.USER), any(UUID.class)))
            .thenReturn(new PayoutApi.ConnectStatus(true, "acct_1", true, false, "an ID document"));
        when(wallet.statement(eq(OwnerKind.USER), any(UUID.class), anyInt())).thenReturn(List.of(
            new WalletApi.Entry(UUID.randomUUID(), 700, "USD", LedgerKind.TIP, "ORDER",
                UUID.randomUUID(), "Tip", OffsetDateTime.now()),
            new WalletApi.Entry(UUID.randomUUID(), -250, "USD", LedgerKind.TOKEN_PURCHASE,
                "TOKENS", UUID.randomUUID(), "12 ride tokens", OffsetDateTime.now())));

        WorkerWalletDto dto = money.wallet(WORKER_USER);

        assertThat(dto.currency()).isEqualTo("USD");
        assertThat(dto.payoutsConfigured()).isTrue();
        assertThat(dto.payoutsReady()).isFalse();
        assertThat(dto.payoutsRequirement()).isEqualTo("an ID document");
        assertThat(dto.payoutMinMinor()).isEqualTo(1_000);
        assertThat(dto.recent()).extracting(WorkerTransactionDto::amountMinor)
            .containsExactly(700L, -250L);
        assertThat(dto.recent()).extracting(WorkerTransactionDto::kind)
            .containsExactly("TIP", "TOKEN_PURCHASE");
    }

    @Test
    @DisplayName("the statement is asked for as the worker, on the worker's own user id")
    void theWalletIsTheirs() {
        availableMinor = 0;

        money.wallet(WORKER_USER);

        // A wallet keyed on the worker row rather than the person would be a
        // dual-mode driver with two balances, which is not what the ledger holds.
        verify(wallet).balancesOf(OwnerKind.USER, WORKER_USER);
        verify(wallet).statement(OwnerKind.USER, WORKER_USER, 25);
    }

    // MARK: Fixtures

    private void earned(LedgerKind kind, long amountMinor) {
        credited.merge(kind, amountMinor, Long::sum);
    }

    private static Worker worker(UUID userId, WorkerKind kind) {
        Worker worker = new Worker(userId, kind, UUID.randomUUID(), VehicleCategory.SCOOTER,
            "Casa", new VehicleRef(UUID.randomUUID(), VehicleCategory.SCOOTER,
                "Red scooter", "12345-A-6", false));
        set(worker, "id", UUID.randomUUID());
        return worker;
    }

    private static void set(Object entity, String field, Object value) {
        try {
            Field f = entity.getClass().getDeclaredField(field);
            f.setAccessible(true);
            f.set(entity, value);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(e);
        }
    }
}
