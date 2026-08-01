package com.gojogo.payments;

import java.util.UUID;

/**
 * Ride-hailing tokens, in tokens.
 *
 * <p>{@link WalletApi} could do all of this — a token movement is a transfer
 * into or out of the TOKENS bucket, and nothing more. This interface exists
 * because of the <em>unit</em>: the ledger holds minor units, a driver counts
 * tokens, and the conversion between them is a policy value
 * ({@code payments.token.value.minor}) that belongs to this module. A vertical
 * that read the balance in minor units and divided it itself would be a second
 * place that knows what a token is worth, and the first time the value changed
 * they would disagree.
 *
 * <p>So callers here speak in whole tokens and never see the conversion. What a
 * <em>ride</em> costs in tokens is not this module's business either — that is
 * keyed by vehicle category and distance, and lives in {@code travel}
 * (ARCHITECTURE §2b decision 2: payments knows amounts and who is owed, never
 * what was bought).
 *
 * <p>Every write is idempotency-keyed, on the same contract {@code WalletApi}
 * states: derive the key from the thing being paid for, never from a clock.
 */
public interface TokenApi {

    /** What one token is worth in minor units. The only conversion in the
     *  system, so that there is only one. */
    long minorPerToken();

    /** How many whole tokens this person has. Rounded <em>down</em>: a partial
     *  token cannot be spent, so counting it would be a promise. */
    long balanceOf(UUID userId);

    /**
     * Charges a driver for taking a job. TOKENS → the platform, which is the
     * platform's entire revenue on a ride (SPECS §1 — rides carry no
     * commission).
     *
     * @throws InsufficientFundsException when they haven't got them. The caller
     *         decides what that means; it is never a reason to unwind a trip
     *         somebody is already waiting for
     */
    WalletApi.Movement spend(UUID userId, long tokens, WalletApi.Reference ref,
                             String idempotencyKey);

    /**
     * Gives tokens back — the platform's side of a job that did not happen.
     *
     * <p>Safe to call for a spend that never landed: it returns
     * {@code alreadyApplied} on a repeat, and a refund of zero moves nothing.
     */
    WalletApi.Movement refund(UUID userId, long tokens, WalletApi.Reference ref,
                              String idempotencyKey);

    /** Tokens from the platform that nobody paid for — a welcome grant, a
     *  goodwill credit. Funded by PLATFORM, so the entries still balance. */
    WalletApi.Movement grant(UUID userId, long tokens, WalletApi.Reference ref,
                             String idempotencyKey);
}
