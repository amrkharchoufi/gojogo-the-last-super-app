package com.gojogo.payments.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.payments.Bucket;
import com.gojogo.payments.LedgerKind;
import com.gojogo.payments.OwnerKind;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.transaction.PlatformTransactionManager;

import java.lang.reflect.Field;
import java.util.Collection;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The two lifetime totals Phase 4 M2 added, and the reasons they are shaped the
 * way they are.
 *
 * <p>Both exist to bound a withdrawal by work actually done, and both are the
 * kind of number a ledger should be reluctant to expose — so what is asserted
 * here is mostly *what they refuse to count*. The arithmetic itself is a
 * database `sum` and cannot run on this machine (there is no local Postgres);
 * what can be pinned is the question being asked, which is where the two bugs
 * worth having would live.
 */
class EarningsAggregateTests {

    private static final UUID WORKER = UUID.randomUUID();

    private AccountRepository accounts;
    private LedgerEntryRepository entries;
    private LedgerService ledger;

    @BeforeEach
    void setUp() {
        accounts = mock(AccountRepository.class);
        entries = mock(LedgerEntryRepository.class);
        ConfigApi config = mock(ConfigApi.class);
        when(config.string(anyString(), anyString()))
            .thenAnswer(call -> call.getArgument(1, String.class));
        ledger = new LedgerService(accounts, entries, config,
            mock(ApplicationEventPublisher.class));
    }

    @Test
    @DisplayName("the total is summed over every pocket this owner has, in the "
        + "platform currency")
    void everyPocketCounts() {
        Account available = account(Bucket.AVAILABLE);
        Account rewards = account(Bucket.REWARDS);
        when(accounts.findByOwnerKindAndOwnerIdAndCurrency(OwnerKind.USER, WORKER, "USD"))
            .thenReturn(List.of(available, rewards));
        when(entries.totalCredited(any(), any())).thenReturn(7_500L);

        long total = ledger.totalByKind(OwnerKind.USER, WORKER,
            Set.of(LedgerKind.COURIER_FEE, LedgerKind.TIP));

        assertThat(total).isEqualTo(7_500);
        // A verification reward lands in REWARDS, not AVAILABLE — asking only
        // about the spendable pocket would lose it.
        ArgumentCaptor<Collection<UUID>> asked = captor();
        verify(entries).totalCredited(asked.capture(), any());
        assertThat(asked.getValue())
            .containsExactlyInAnyOrder(idOf(available), idOf(rewards));
    }

    @Test
    @DisplayName("somebody with no accounts is zero, and the database is not asked")
    void noAccountsIsZeroWithoutAQuery() {
        when(accounts.findByOwnerKindAndOwnerIdAndCurrency(OwnerKind.USER, WORKER, "USD"))
            .thenReturn(List.of());

        assertThat(ledger.totalByKind(OwnerKind.USER, WORKER, Set.of(LedgerKind.TIP))).isZero();
        // Not an optimisation: an empty list inside an `in (…)` is a syntax
        // error, so this guard is the difference between a zero and a 500 on the
        // first wallet screen a new courier ever opens.
        verify(entries, never()).totalCredited(any(), any());
    }

    @Test
    @DisplayName("an empty set of kinds is nothing, not everything")
    void noKindsIsZero() {
        assertThat(ledger.totalByKind(OwnerKind.USER, WORKER, Set.of())).isZero();
        assertThat(ledger.totalByKind(OwnerKind.USER, WORKER, null)).isZero();

        // The safe direction to be wrong in: a caller that computed its own kind
        // list and got nothing meant nothing, and answering "all of it" would
        // uncap a withdrawal.
        verify(entries, never()).totalCredited(any(), any());
    }

    @Test
    @DisplayName("a payout that failed is not money that left")
    void failedPayoutsAreNotCountedAsPaidOut() {
        PayoutRepository payouts = mock(PayoutRepository.class);
        PayoutService service = new PayoutService(ledger, mock(StripeClient.class),
            mock(ConfigApi.class), mock(ConnectAccountRepository.class), payouts,
            mock(ApplicationEventPublisher.class), mock(PlatformTransactionManager.class));
        when(payouts.totalMinor(eq(OwnerKind.USER), eq(WORKER), any())).thenReturn(4_000L);

        assertThat(service.lifetimePaidOutMinor(OwnerKind.USER, WORKER)).isEqualTo(4_000);

        // The decision this method exists for. A refused transfer leaves its
        // PAYOUT debit standing and reverses it with an ADJUSTMENT, so counting
        // the FAILED row — or summing the ledger kind, which is the same
        // mistake — would hold a withdrawal that never happened against somebody
        // for good. A REQUESTED one *is* counted: it has been debited and may
        // yet land, and ignoring it would let a second withdrawal out alongside
        // the first.
        ArgumentCaptor<Collection<Payout.Status>> asked = captor();
        verify(payouts).totalMinor(eq(OwnerKind.USER), eq(WORKER), asked.capture());
        assertThat(asked.getValue())
            .containsExactlyInAnyOrder(Payout.Status.REQUESTED, Payout.Status.SENT);
    }

    // MARK: Fixtures

    @SuppressWarnings("unchecked")
    private static <T> ArgumentCaptor<Collection<T>> captor() {
        return ArgumentCaptor.forClass((Class<Collection<T>>) (Class<?>) Collection.class);
    }

    private static Account account(Bucket bucket) {
        Account account = new Account();
        set(account, "id", UUID.randomUUID());
        set(account, "ownerKind", OwnerKind.USER);
        set(account, "ownerId", WORKER);
        set(account, "bucket", bucket);
        set(account, "currency", "USD");
        return account;
    }

    private static UUID idOf(Account account) {
        try {
            Field f = Account.class.getDeclaredField("id");
            f.setAccessible(true);
            return (UUID) f.get(account);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(e);
        }
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
