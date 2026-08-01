package com.gojogo.payments.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.payments.Bucket;
import com.gojogo.payments.LedgerKind;
import com.gojogo.payments.OwnerKind;
import com.gojogo.payments.WalletApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.Pageable;

import java.lang.reflect.Field;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * What a statement shows, and which way round.
 *
 * <p>Both rules here were found by Phase 3 M4. Buying ride tokens moves money
 * between two of the driver's own pockets, which the original statement dropped
 * as bookkeeping — so a wallet balance fell by eleven dollars with no line
 * anywhere to say why. And the same movement has two honest signs: on a wallet
 * it is money out, on a token screen it is tokens in.
 */
class StatementTests {

    private static final UUID USER = UUID.randomUUID();

    private AccountRepository accounts;
    private LedgerEntryRepository entries;
    private LedgerService ledger;

    private Account available;
    private Account tokens;
    private Account staking;

    @BeforeEach
    void setUp() {
        accounts = mock(AccountRepository.class);
        entries = mock(LedgerEntryRepository.class);
        ConfigApi config = mock(ConfigApi.class);
        when(config.string(anyString(), anyString()))
            .thenAnswer(call -> call.getArgument(1, String.class));
        ledger = new LedgerService(accounts, entries, config,
            mock(ApplicationEventPublisher.class));

        available = account(Bucket.AVAILABLE);
        tokens = account(Bucket.TOKENS);
        staking = account(Bucket.STAKING);
        when(accounts.findByOwnerKindAndOwnerIdAndCurrency(OwnerKind.USER, USER, "USD"))
            .thenReturn(List.of(available, tokens, staking));
    }

    @Test
    @DisplayName("buying tokens is a line on the wallet, signed as money leaving")
    void ownBucketPurchasesAreShown() {
        given(entry(available, tokens, 1_100, LedgerKind.TOKEN_PURCHASE, "12 ride tokens"));

        List<WalletApi.Entry> statement = ledger.statement(OwnerKind.USER, USER, 50);

        // Dropping it — which is what "an entry between two of their own buckets
        // is bookkeeping" used to do — left a wallet that fell by eleven dollars
        // with nothing anywhere to explain it.
        assertThat(statement).singleElement()
            .satisfies(line -> assertThat(line.amountMinor()).isEqualTo(-1_100));
    }

    @Test
    @DisplayName("a stake reads as money out and its release as money back")
    void stakesAreSignedFromTheSpendablePocket() {
        given(entry(available, staking, 3_000, LedgerKind.STAKE, "Driver stake"),
            entry(staking, available, 3_000, LedgerKind.STAKE_RELEASE, "Stake returned"));

        assertThat(ledger.statement(OwnerKind.USER, USER, 50))
            .extracting(WalletApi.Entry::amountMinor)
            .containsExactly(-3_000L, 3_000L);
    }

    @Test
    @DisplayName("a hold is still bookkeeping and still says nothing")
    void holdsStayHidden() {
        Account escrow = account(Bucket.ESCROW);
        when(accounts.findByOwnerKindAndOwnerIdAndCurrency(OwnerKind.USER, USER, "USD"))
            .thenReturn(List.of(available, tokens, staking, escrow));
        given(entry(available, escrow, 2_500, LedgerKind.HOLD, "Lunch"));

        // Nothing left, and a push for it would train people to ignore the ones
        // that matter.
        assertThat(ledger.statement(OwnerKind.USER, USER, 50)).isEmpty();
    }

    @Test
    @DisplayName("the token pocket's own history signs the same purchase the other way")
    void thePocketDecidesTheSign() {
        when(accounts.findByOwnerKindAndOwnerIdAndBucketAndCurrency(
            OwnerKind.USER, USER, Bucket.TOKENS, "USD")).thenReturn(Optional.of(tokens));
        given(entry(available, tokens, 1_100, LedgerKind.TOKEN_PURCHASE, "12 ride tokens"),
            entry(tokens, account(Bucket.AVAILABLE), 200, LedgerKind.TOKEN_SPEND, "trip"));

        // The same movement, read from the pocket it filled: eleven tokens
        // gained, not eleven dollars gone. Borrowing the wallet's sign would show
        // a driver "−11" for the tokens they just bought.
        assertThat(ledger.bucketStatement(OwnerKind.USER, USER, Bucket.TOKENS, 30))
            .extracting(WalletApi.Entry::amountMinor)
            .containsExactly(1_100L, -200L);
    }

    @Test
    @DisplayName("a pocket that has never been used has no history and no error")
    void anUnusedBucketIsEmpty() {
        when(accounts.findByOwnerKindAndOwnerIdAndBucketAndCurrency(
            OwnerKind.USER, USER, Bucket.REWARDS, "USD")).thenReturn(Optional.empty());

        assertThat(ledger.bucketStatement(OwnerKind.USER, USER, Bucket.REWARDS, 30)).isEmpty();
    }

    // MARK: Fixtures

    private void given(LedgerEntry... rows) {
        when(entries.statement(any(), any(Pageable.class))).thenReturn(List.of(rows));
    }

    private static Account account(Bucket bucket) {
        Account account = new Account();
        set(account, "id", UUID.randomUUID());
        set(account, "ownerKind", OwnerKind.USER);
        set(account, "ownerId", USER);
        set(account, "bucket", bucket);
        set(account, "currency", "USD");
        return account;
    }

    private static LedgerEntry entry(Account from, Account to, long amountMinor,
                                     LedgerKind kind, String memo) {
        LedgerEntry entry = new LedgerEntry("key-" + UUID.randomUUID(), idOf(from), idOf(to),
            amountMinor, "USD", kind, "", null, memo);
        set(entry, "id", UUID.randomUUID());
        return entry;
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
