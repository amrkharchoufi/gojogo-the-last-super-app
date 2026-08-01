package com.gojogo.payments.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.payments.AccountRef;
import com.gojogo.payments.Bucket;
import com.gojogo.payments.LedgerKind;
import com.gojogo.payments.OwnerKind;
import com.gojogo.payments.TokenApi;
import com.gojogo.payments.TokensRanOut;
import com.gojogo.payments.WalletApi;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/**
 * Tokens: buying them, spending them, and the one conversion between a token and
 * money.
 *
 * <p><strong>A pack is bought out of the wallet, not off a card.</strong> SPECS
 * §1 has it as "Stripe → TOKENS credit at pack rate", but 2e M3 already settled
 * the shape of card money in this platform: it always arrives as a wallet
 * top-up, never as a per-purchase charge. Keeping that rule means one Stripe
 * integration, one webhook and one place a payment can go wrong — and a driver
 * whose wallet is short gets a top-up for exactly the shortfall, which is the
 * flow the $30 stake already uses and the app already draws.
 *
 * <p><strong>The bonus is the platform's entry, not free money.</strong> Twelve
 * tokens for the price of eleven is two movements: eleven from the driver, one
 * from PLATFORM. A ledger where a discount appears as a credit with no debit is
 * a ledger that stops adding up, and the nightly audit would find it.
 */
@Service
class TokenService implements TokenApi {

    private static final String VALUE_KEY = "payments.token.value.minor";
    private static final String LOW_KEY = "payments.tokens.low.threshold";
    private static final long VALUE_DEFAULT = 100;
    private static final long LOW_DEFAULT = 3;

    private final LedgerService ledger;
    private final LedgerEntryRepository entries;
    private final TokenPackRepository packs;
    private final ConfigApi config;
    private final ApplicationEventPublisher events;

    TokenService(LedgerService ledger, LedgerEntryRepository entries, TokenPackRepository packs,
                 ConfigApi config, ApplicationEventPublisher events) {
        this.ledger = ledger;
        this.entries = entries;
        this.packs = packs;
        this.config = config;
        this.events = events;
    }

    // MARK: TokenApi

    @Override
    public long minorPerToken() {
        // Floored at 1: a token worth nothing would make every ride free and
        // every purchase a donation, and a zero here is always a typo.
        return Math.max(1, config.number(VALUE_KEY, VALUE_DEFAULT));
    }

    @Override
    @Transactional(readOnly = true)
    public long balanceOf(UUID userId) {
        return tokensIn(ledger.balancesOf(OwnerKind.USER, userId).tokens());
    }

    @Override
    @Transactional
    public WalletApi.Movement spend(UUID userId, long tokens, WalletApi.Reference ref,
                                    String idempotencyKey) {
        if (tokens <= 0) return nothingMoved();
        WalletApi.Movement movement = ledger.post(
            AccountRef.user(userId, Bucket.TOKENS),
            AccountRef.platform(),
            tokens * minorPerToken(), LedgerKind.TOKEN_SPEND, ref, idempotencyKey);
        if (!movement.alreadyApplied()) warnIfLow(userId);
        return movement;
    }

    @Override
    @Transactional
    public WalletApi.Movement refund(UUID userId, long tokens, WalletApi.Reference ref,
                                     String idempotencyKey) {
        if (tokens <= 0) return nothingMoved();
        return ledger.post(
            AccountRef.platform(),
            AccountRef.user(userId, Bucket.TOKENS),
            tokens * minorPerToken(), LedgerKind.REFUND, ref, idempotencyKey);
    }

    @Override
    @Transactional
    public WalletApi.Movement grant(UUID userId, long tokens, WalletApi.Reference ref,
                                    String idempotencyKey) {
        if (tokens <= 0) return nothingMoved();
        return ledger.post(
            AccountRef.platform(),
            AccountRef.user(userId, Bucket.TOKENS),
            tokens * minorPerToken(), LedgerKind.TOKEN_PURCHASE, ref, idempotencyKey);
    }

    // MARK: The driver's screen

    @Transactional(readOnly = true)
    Dtos.TokenWalletDto wallet(UUID userId) {
        long minorPerToken = minorPerToken();
        WalletApi.Balances balances = ledger.balancesOf(OwnerKind.USER, userId);
        return new Dtos.TokenWalletDto(
            tokensIn(balances.tokens()), balances.tokens(), minorPerToken,
            balances.available(), balances.currency(), lowThreshold(),
            packs.findByActiveTrueOrderBySortOrderAsc().stream()
                .map(pack -> toDto(pack, minorPerToken))
                .toList(),
            recentTokenMovements(userId));
    }

    /**
     * Buys a pack.
     *
     * <p>The purchase and the bonus are two entries in one transaction, in that
     * order. If the wallet cannot cover the price the first one throws and the
     * second never happens — which is the whole reason the bonus is second: a
     * driver credited a bonus for a pack they did not manage to buy is a hole
     * that only surfaces in a monthly reconciliation.
     *
     * <p>The key counts this person's previous purchases of this pack rather
     * than reading a clock, so two taps a millisecond apart collapse onto one
     * purchase while buying the same pack again tomorrow is genuinely a second.
     */
    @Transactional
    Dtos.TokenWalletDto purchase(UUID userId, UUID packId) {
        TokenPack pack = packs.findById(packId)
            .filter(TokenPack::isActive)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "That token pack isn't on sale"));
        long minorPerToken = minorPerToken();
        String prefix = "tokenpack:" + userId + ":" + pack.getId() + ":";
        long already = entries.countByIdempotencyKeyStartingWith(prefix);
        WalletApi.Reference ref = WalletApi.Reference.of("TOKEN_PACK", pack.getId(),
            pack.getTokens() + " ride tokens");

        ledger.post(AccountRef.user(userId, Bucket.AVAILABLE),
            AccountRef.user(userId, Bucket.TOKENS),
            pack.getPriceMinor(), LedgerKind.TOKEN_PURCHASE, ref, prefix + already);

        long bonus = pack.bonusMinor(minorPerToken);
        if (bonus > 0) {
            // A different prefix, so the bonus never counts itself into the key
            // of the next purchase.
            ledger.post(AccountRef.platform(),
                AccountRef.user(userId, Bucket.TOKENS),
                bonus, LedgerKind.TOKEN_PURCHASE,
                WalletApi.Reference.of("TOKEN_PACK", pack.getId(),
                    pack.getName() + " pack bonus"),
                "tokenbonus:" + userId + ":" + pack.getId() + ":" + already);
        }
        return wallet(userId);
    }

    // MARK: Helpers

    long lowThreshold() {
        return Math.max(0, config.number(LOW_KEY, LOW_DEFAULT));
    }

    /**
     * Whole tokens only. A balance of 150 minor at 100 a token is one token, not
     * one and a half: the half cannot buy anything, and showing it would leave a
     * driver watching a number that never becomes a ride.
     */
    private long tokensIn(long minor) {
        return Math.max(0, minor / minorPerToken());
    }

    /**
     * Tells a driver they are nearly out, at the moment they spend.
     *
     * <p>Deliberately not a sweep. A balance that has been sitting at one token
     * for a week is not news, and a nightly job announcing it to everybody who
     * has ever driven is the notification people turn off.
     */
    private void warnIfLow(UUID userId) {
        long threshold = lowThreshold();
        if (threshold <= 0) return;
        long remaining = balanceOf(userId);
        if (remaining > threshold) return;
        events.publishEvent(new TokensRanOut(userId, remaining, threshold,
            OffsetDateTime.now()));
    }

    /**
     * The TOKENS pocket's own history, signed from <em>its</em> point of view.
     *
     * <p>Not a filtered wallet statement, and the difference matters: buying
     * tokens is money leaving AVAILABLE and tokens arriving in TOKENS. On the
     * wallet it is a debit; here it is eleven tokens gained, and borrowing the
     * wallet's sign would show a driver "−11" for the eleven they just bought.
     */
    private List<Dtos.TransactionDto> recentTokenMovements(UUID userId) {
        return ledger.bucketStatement(OwnerKind.USER, userId, Bucket.TOKENS, 30).stream()
            .map(entry -> new Dtos.TransactionDto(entry.id(), entry.amountMinor(),
                entry.currency(), entry.kind().name(), entry.refKind(), entry.refId(),
                entry.memo(), entry.createdAt()))
            .toList();
    }

    private Dtos.TokenPackDto toDto(TokenPack pack, long minorPerToken) {
        return new Dtos.TokenPackDto(pack.getId(), pack.getName(), pack.getTokens(),
            pack.getPriceMinor(), pack.bonusMinor(minorPerToken) / minorPerToken,
            pack.getNote());
    }

    /** A movement that did not need to happen — a zero-token ride, a refund of
     *  nothing. Reported rather than thrown, so those read like any other. */
    private static WalletApi.Movement nothingMoved() {
        return new WalletApi.Movement(null, 0, true);
    }
}
