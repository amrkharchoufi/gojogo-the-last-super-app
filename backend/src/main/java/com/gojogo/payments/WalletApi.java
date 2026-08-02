package com.gojogo.payments;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * How every other module moves money. The only door into the ledger.
 *
 * <p>Amounts are integer <strong>minor units</strong> of the single platform
 * currency ({@link #currency()}) — there is no decimal arithmetic anywhere in
 * this system, because floating-point money is a category of bug rather than an
 * implementation detail. Multi-currency is deferred (SPECS §15); until it isn't,
 * every account is in that one currency and a caller never has to say which.
 *
 * <p><strong>Every write takes an idempotency key</strong> that is unique in the
 * database. Call twice with the same key and the second call changes nothing and
 * reports {@link Movement#alreadyApplied()}. Keys should be derived from the
 * thing being paid for — {@code "order:" + orderId + ":hold"} — rather than
 * generated, so that a client retry, a webhook replay and a redelivered event
 * all collapse onto one movement.
 */
public interface WalletApi {

    /** ISO 4217, upper case. Single-currency platform (SPECS §15). */
    String currency();

    Balances balancesOf(OwnerKind ownerKind, UUID ownerId);

    /**
     * Moves the owner's own money from AVAILABLE into their ESCROW: taken out
     * of circulation, still theirs. This is what a checkout does.
     *
     * @throws InsufficientFundsException when AVAILABLE won't cover it — the
     *         caller is expected to turn that into "top up your wallet" rather
     *         than a failure
     */
    Movement hold(OwnerKind ownerKind, UUID ownerId, long amountMinor,
                  Reference ref, String idempotencyKey);

    /** ESCROW back to AVAILABLE — the order was cancelled before settlement. */
    Movement release(OwnerKind ownerKind, UUID ownerId, long amountMinor,
                     Reference ref, String idempotencyKey);

    /**
     * Settles a hold: the payer's ESCROW is split among its payees in one
     * transaction, all of it or none.
     *
     * <p>The splits must sum to exactly what was held. Capturing less than the
     * hold silently strands money in escrow, which is the kind of error nobody
     * notices for a month, so it is rejected rather than tolerated — release
     * the difference explicitly if that is what was meant.
     *
     * @param idempotencyKey the key for the settlement as a whole; each split
     *                       derives its own from it, so a retry is safe
     */
    List<Movement> capture(OwnerKind payerKind, UUID payerId, List<Split> splits,
                           Reference ref, String idempotencyKey);

    /** Any account to any other account. The general form the named verbs are
     *  conveniences over. */
    Movement transfer(AccountRef from, AccountRef to, long amountMinor, LedgerKind kind,
                      Reference ref, String idempotencyKey);

    /**
     * Money going back after a capture. A reversal, not an edit: the original
     * entries stay exactly as they were and this one says so. Partial refunds
     * are just smaller amounts.
     */
    Movement refund(AccountRef from, AccountRef to, long amountMinor,
                    Reference ref, String idempotencyKey);

    /** Everything that touched this owner's accounts, newest first. */
    List<Entry> statement(OwnerKind ownerKind, UUID ownerId, int limit);

    /** Everything that happened to one thing — the receipt query, and what a
     *  dispute is argued from. */
    List<Entry> entriesFor(String refKind, UUID refId);

    /**
     * Lifetime total of money that <em>arrived</em> on this owner's accounts
     * under these kinds, as a positive number.
     *
     * <p>The one aggregate this ledger exposes, and it should stay the only one.
     * A ledger's job is to say what happened, entry by entry; a sum is a derived
     * number that will eventually disagree with the entries it came from, and
     * the moment a screen shows one, somebody will want it stored in a column
     * where it can drift for real. This one exists because a payout out of a
     * bucket that also holds top-up money has to be bounded by work actually
     * done, and that bound cannot be computed from a balance — a balance has
     * forgotten where its money came from. Only the entries remember.
     *
     * <p><strong>Credits only.</strong> An entry counts when one of this owner's
     * accounts is on the <em>receiving</em> side, which is what makes the answer
     * "what you were paid" rather than "what passed through you". The difference
     * is not academic: a vehicle-verification {@code REWARD} is paid out of one
     * driver's STAKING into another person's REWARDS, so a sum that counted both
     * sides would hand the driver who funded it the earnings of the passenger
     * who collected it.
     *
     * @param kinds an empty set is 0 rather than everything — a caller that
     *              computed its own kind list and got nothing meant nothing
     */
    long totalByKind(OwnerKind ownerKind, UUID ownerId, Set<LedgerKind> kinds);

    /**
     * What a movement was about: {@code ("ORDER", orderId, "Lunch at Pizza
     * Place")}. The memo is shown on statements, so it must never carry an
     * address, a card, or anything else that would make the ledger sensitive.
     */
    record Reference(String kind, UUID id, String memo) {

        public static Reference of(String kind, UUID id, String memo) {
            return new Reference(kind == null ? "" : kind, id, memo == null ? "" : memo);
        }
    }

    /** One payee's share of a settlement. */
    record Split(AccountRef payee, long amountMinor, LedgerKind kind, String memo) {
    }

    /**
     * The outcome of a write.
     *
     * @param alreadyApplied true when this exact idempotency key had already
     *                       been used — nothing moved, and {@code entryId} is
     *                       the movement that did happen
     */
    record Movement(UUID entryId, long amountMinor, boolean alreadyApplied) {
    }

    /** One line of a statement, from the reader's point of view: {@code
     *  amountMinor} is signed — negative when money left this owner. */
    record Entry(UUID id, long amountMinor, String currency, LedgerKind kind,
                 String refKind, UUID refId, String memo, OffsetDateTime createdAt) {
    }

    /** The five pockets, all in {@link #currency()}. */
    record Balances(String currency, long available, long escrow, long staking,
                    long tokens, long rewards) {

        public static Balances empty(String currency) {
            return new Balances(currency, 0, 0, 0, 0, 0);
        }

        /** What the owner could spend right now. */
        public long spendable() {
            return available;
        }
    }
}
