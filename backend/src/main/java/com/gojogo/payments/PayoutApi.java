package com.gojogo.payments;

import java.util.UUID;

/**
 * Getting money out of the platform — the Stripe Connect half of SPECS.md §1.
 *
 * <p>Separate from {@link WalletApi} because it is a different kind of act:
 * everything in the wallet is internal and instant, while a payout leaves the
 * platform, depends on a vendor's onboarding state, and can be refused for
 * reasons no amount of balance fixes.
 *
 * <p>Called by whichever module owns the payee — {@code delivery} for a
 * merchant, {@code dispatch} for a driver or courier later — because that module
 * is the one that can prove the caller owns the account being paid. Payments
 * knows what is owed; it does not know who is allowed to ask for it.
 */
public interface PayoutApi {

    /** Whether Stripe is configured at all. Unset credentials mean the wallet
     *  still works for every internal movement and only the outside world is
     *  unreachable — the same "unconfigured is a mode, not a failure" posture
     *  the KYC module takes. */
    boolean isConfigured();

    ConnectStatus statusOf(OwnerKind ownerKind, UUID ownerId);

    /**
     * A single-use Stripe-hosted onboarding URL for this payee, creating their
     * connected account on first ask.
     *
     * <p>The link is short-lived by Stripe's design and must not be stored or
     * shared: it authenticates whoever opens it as the account holder.
     *
     * @param email prefills the form; the payee can change it
     */
    String onboardingLink(OwnerKind ownerKind, UUID ownerId, String email);

    /**
     * Pays out from the payee's AVAILABLE bucket to their connected account.
     *
     * <p>The ledger is debited first and the transfer attempted second. A payout
     * that paid out without debiting is unrecoverable; one that debited and
     * failed to pay is a FAILED row and a release entry, which is a Tuesday.
     *
     * <p>The {@code guard} is the owning module's own limit — a driver's
     * earned-cap, say — and it is run <em>inside</em> the debit transaction,
     * after this payee's balance row is locked and before any money moves. That
     * placement is the whole point: a cap checked before the lock is a cap two
     * simultaneous requests both pass, each reading a balance the other is about
     * to spend. Under the lock, the second request blocks until the first
     * commits its payout row, then re-runs the guard against a total that already
     * counts it. The guard throws (a {@code ResponseStatusException}) to refuse;
     * a payee with no such limit passes a no-op.
     *
     * @throws InsufficientFundsException when the balance won't cover it
     */
    PayoutResult payOut(OwnerKind ownerKind, UUID ownerId, UUID requestedBy, long amountMinor,
                        PayoutGuard guard);

    /**
     * A last check run under the payee's balance lock, just before the debit.
     * Throw to refuse the payout; return to allow it. See {@link #payOut}.
     */
    @FunctionalInterface
    interface PayoutGuard {
        void check();

        /** For a payee the platform pays without an earned-cap (a merchant's
         *  balance is only ever earnings). Cooldown and balance still apply. */
        static PayoutGuard none() {
            return () -> { };
        }
    }

    /**
     * Everything this payee has already had sent out of the platform, in minor
     * units. For a caller that has to bound the next withdrawal by the last
     * ones.
     *
     * <p>Read from the payout rows rather than by summing {@code PAYOUT} ledger
     * entries, and the difference matters exactly once: a payout the provider
     * refuses leaves its debit entry standing and reverses it with an
     * {@code ADJUSTMENT}, because the ledger is append-only and a mistake there
     * is another entry rather than an edit. Summing the kind would count that
     * failed payout as money that left, and a caller using the total as a cap
     * would then hold it against somebody forever — for a transfer that never
     * happened. The rows know the difference; the kinds do not.
     *
     * <p>Counts everything not FAILED. A row still {@code REQUESTED} has been
     * debited and may yet land, and a cap that ignored one would let a second
     * request go out while the first was in flight.
     */
    long lifetimePaidOutMinor(OwnerKind ownerKind, UUID ownerId);

    /**
     * @param stripeAccountId  null until the payee has started onboarding
     * @param requirementsNote Stripe's own words about what is still missing —
     *                         shown to the payee, since only they can fix it
     */
    record ConnectStatus(boolean exists, String stripeAccountId, boolean detailsSubmitted,
                         boolean payoutsEnabled, String requirementsNote) {

        public static ConnectStatus none() {
            return new ConnectStatus(false, null, false, false, "");
        }

        /** Ready to be paid. */
        public boolean ready() {
            return exists && payoutsEnabled;
        }
    }

    record PayoutResult(UUID payoutId, long amountMinor, String currency, String status,
                        String failureReason) {
    }
}
