package com.gojogo.payments.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.payments.AccountRef;
import com.gojogo.payments.Bucket;
import com.gojogo.payments.InsufficientFundsException;
import com.gojogo.payments.LedgerKind;
import com.gojogo.payments.OwnerKind;
import com.gojogo.payments.TokensRanOut;
import com.gojogo.payments.WalletApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.web.server.ResponseStatusException;

import java.lang.reflect.Field;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Buying and spending tokens.
 *
 * <p>The one that matters most is the bonus. A pack that gives twelve tokens for
 * the price of eleven is a discount, and a discount in a double-entry ledger has
 * to come from somewhere — credit the extra without debiting anybody and the
 * books stop balancing, quietly, once per purchase, until the nightly audit
 * finds a platform account that no longer adds up.
 */
class TokenPurchaseTests {

    private static final UUID DRIVER = UUID.randomUUID();

    private LedgerService ledger;
    private LedgerEntryRepository entries;
    private TokenPackRepository packs;
    private ApplicationEventPublisher events;
    private TokenService tokens;

    @BeforeEach
    void setUp() {
        ledger = mock(LedgerService.class);
        entries = mock(LedgerEntryRepository.class);
        packs = mock(TokenPackRepository.class);
        events = mock(ApplicationEventPublisher.class);
        ConfigApi config = mock(ConfigApi.class);
        when(config.number(anyString(), anyLong()))
            .thenAnswer(call -> call.getArgument(1, Long.class));

        when(ledger.post(any(), any(), anyLong(), any(), any(), anyString()))
            .thenReturn(new WalletApi.Movement(UUID.randomUUID(), 0, false));
        when(ledger.balancesOf(any(), any()))
            .thenReturn(new WalletApi.Balances("USD", 10_000, 0, 0, 0, 0));
        when(ledger.bucketStatement(any(), any(), any(), anyInt())).thenReturn(List.of());
        when(entries.countByIdempotencyKeyStartingWith(anyString())).thenReturn(0L);

        tokens = new TokenService(ledger, entries, packs, config, events);
    }

    // MARK: Buying

    @Test
    @DisplayName("a discounted pack is two entries: the driver's money and the platform's")
    void theBonusIsFundedNotInvented() {
        TokenPack pack = pack("Standard", 12, 1_100);
        when(packs.findById(pack.getId())).thenReturn(Optional.of(pack));

        tokens.purchase(DRIVER, pack.getId());

        // 12 tokens are worth 1200; the driver pays 1100 and the platform pays
        // the last 100. Nothing is created.
        verify(ledger).post(eq(AccountRef.user(DRIVER, Bucket.AVAILABLE)),
            eq(AccountRef.user(DRIVER, Bucket.TOKENS)), eq(1_100L),
            eq(LedgerKind.TOKEN_PURCHASE), any(), anyString());
        verify(ledger).post(eq(AccountRef.platform()),
            eq(AccountRef.user(DRIVER, Bucket.TOKENS)), eq(100L),
            eq(LedgerKind.TOKEN_PURCHASE), any(), anyString());
    }

    @Test
    @DisplayName("a pack at face value writes one entry, not a bonus of zero")
    void noBonusNoEntry() {
        TokenPack pack = pack("Starter", 5, 500);
        when(packs.findById(pack.getId())).thenReturn(Optional.of(pack));

        tokens.purchase(DRIVER, pack.getId());

        verify(ledger, never()).post(eq(AccountRef.platform()), any(), anyLong(), any(),
            any(), anyString());
    }

    @Test
    @DisplayName("the bonus never lands without the purchase")
    void aShortWalletBuysNothingAtAll() {
        TokenPack pack = pack("Fleet", 75, 6_000);
        when(packs.findById(pack.getId())).thenReturn(Optional.of(pack));
        doThrow(new InsufficientFundsException(6_000, 200, "USD"))
            .when(ledger).post(eq(AccountRef.user(DRIVER, Bucket.AVAILABLE)), any(), anyLong(),
                any(), any(), anyString());

        assertThatThrownBy(() -> tokens.purchase(DRIVER, pack.getId()))
            .isInstanceOf(InsufficientFundsException.class);
        // Which is what makes the order of the two entries load-bearing: a bonus
        // credited for a pack nobody managed to buy only surfaces in a monthly
        // reconciliation.
        verify(ledger, never()).post(eq(AccountRef.platform()), any(), anyLong(), any(),
            any(), anyString());
    }

    @Test
    @DisplayName("two taps buy one pack; tomorrow's purchase is genuinely a second")
    void theKeyCountsPurchasesNotSeconds() {
        TokenPack pack = pack("Starter", 5, 500);
        when(packs.findById(pack.getId())).thenReturn(Optional.of(pack));

        tokens.purchase(DRIVER, pack.getId());
        verify(ledger).post(any(), any(), anyLong(), any(), any(),
            eq("tokenpack:" + DRIVER + ":" + pack.getId() + ":0"));

        when(entries.countByIdempotencyKeyStartingWith(anyString())).thenReturn(1L);
        tokens.purchase(DRIVER, pack.getId());
        verify(ledger).post(any(), any(), anyLong(), any(), any(),
            eq("tokenpack:" + DRIVER + ":" + pack.getId() + ":1"));
    }

    @Test
    @DisplayName("a pack that was withdrawn from sale cannot be bought by id")
    void inactivePacksAreGone() {
        TokenPack pack = pack("Retired", 5, 500);
        set(pack, "active", false);
        when(packs.findById(pack.getId())).thenReturn(Optional.of(pack));

        assertThatThrownBy(() -> tokens.purchase(DRIVER, pack.getId()))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("isn't on sale");
    }

    // MARK: Counting

    @Test
    @DisplayName("a part-token is not a token")
    void balancesRoundDown() {
        when(ledger.balancesOf(OwnerKind.USER, DRIVER))
            .thenReturn(new WalletApi.Balances("USD", 0, 0, 0, 250, 0));
        // 250 minor at 100 a token buys two rides, not two and a half, and a
        // driver watching 2.5 would be watching a number that never becomes one.
        assertThat(tokens.balanceOf(DRIVER)).isEqualTo(2);
    }

    // MARK: Spending

    @Test
    @DisplayName("spending the last tokens says so; spending from plenty says nothing")
    void theWarningFiresOnTheWayDown() {
        when(ledger.balancesOf(OwnerKind.USER, DRIVER))
            .thenReturn(new WalletApi.Balances("USD", 0, 0, 0, 100, 0));

        tokens.spend(DRIVER, 2, WalletApi.Reference.of("RIDE", UUID.randomUUID(), "trip"),
            "ride:1:tokens");
        verify(events).publishEvent(any(TokensRanOut.class));

        when(ledger.balancesOf(OwnerKind.USER, DRIVER))
            .thenReturn(new WalletApi.Balances("USD", 0, 0, 0, 5_000, 0));
        tokens.spend(DRIVER, 2, WalletApi.Reference.of("RIDE", UUID.randomUUID(), "trip"),
            "ride:2:tokens");
        verify(events).publishEvent(any(TokensRanOut.class)); // still just the one
    }

    @Test
    @DisplayName("a retried spend moves nothing and warns nobody twice")
    void anAlreadyAppliedSpendIsSilent() {
        when(ledger.post(any(), any(), anyLong(), any(), any(), anyString()))
            .thenReturn(new WalletApi.Movement(UUID.randomUUID(), 200, true));
        when(ledger.balancesOf(OwnerKind.USER, DRIVER))
            .thenReturn(new WalletApi.Balances("USD", 0, 0, 0, 0, 0));

        tokens.spend(DRIVER, 2, WalletApi.Reference.of("RIDE", UUID.randomUUID(), "trip"),
            "ride:1:tokens");

        verify(events, never()).publishEvent(any(TokensRanOut.class));
    }

    @Test
    @DisplayName("a zero-token spend is not a ledger entry")
    void zeroMovesNothing() {
        tokens.spend(DRIVER, 0, WalletApi.Reference.of("RIDE", UUID.randomUUID(), "trip"), "k");
        tokens.refund(DRIVER, 0, WalletApi.Reference.of("RIDE", UUID.randomUUID(), "trip"), "k");
        verify(ledger, never()).post(any(), any(), anyLong(), any(), any(), anyString());
    }

    @Test
    @DisplayName("a grant comes out of the platform, so the entries still balance")
    void grantsHaveAPayer() {
        tokens.grant(DRIVER, 5, WalletApi.Reference.of("PARTNER_WELCOME", DRIVER, "welcome"),
            "partner:1:welcome-tokens");
        verify(ledger).post(eq(AccountRef.platform()),
            eq(AccountRef.user(DRIVER, Bucket.TOKENS)), eq(500L),
            eq(LedgerKind.TOKEN_PURCHASE), any(), anyString());
    }

    // MARK: Fixtures

    private static TokenPack pack(String name, int tokens, long priceMinor) {
        TokenPack pack = new TokenPack();
        set(pack, "id", UUID.randomUUID());
        set(pack, "name", name);
        set(pack, "tokens", tokens);
        set(pack, "priceMinor", priceMinor);
        set(pack, "active", true);
        return pack;
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
