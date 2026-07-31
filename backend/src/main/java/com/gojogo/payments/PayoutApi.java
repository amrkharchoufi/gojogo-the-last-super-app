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
     * @throws InsufficientFundsException when the balance won't cover it
     */
    PayoutResult payOut(OwnerKind ownerKind, UUID ownerId, UUID requestedBy, long amountMinor);

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
