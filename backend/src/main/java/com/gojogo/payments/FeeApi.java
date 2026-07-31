package com.gojogo.payments;

/**
 * What the platform takes, so a vertical can settle without knowing the policy.
 *
 * <p>Separate from {@link WalletApi} because it is a question, not a movement —
 * and because a vertical asks it while *pricing*, long before any money moves.
 *
 * <p>The policy is effective-dated in {@code payments.fee_policy}: the answer is
 * whatever was in force when the settlement happens, which is what keeps a fee
 * change from retroactively altering what an order that already settled was
 * worth. A vertical with no policy row is charged nothing — the safe direction
 * to be wrong in, since the alternative is silently taking money nobody agreed
 * to.
 */
public interface FeeApi {

    /** Verticals, as they appear in {@code payments.fee_policy.vertical}. */
    String DELIVERY = "DELIVERY";
    String ECONOMY = "ECONOMY";
    String TRAVEL = "TRAVEL";
    String SERVICES = "SERVICES";

    /**
     * The platform's cut of {@code baseMinor}, rounded down and never more than
     * the base itself.
     *
     * <p>What counts as the base is the caller's decision and a meaningful one:
     * delivery applies it to the discounted food subtotal only, never to the
     * delivery fee, the tip, or a promotion the merchant is already paying for.
     */
    long platformFee(String vertical, long baseMinor);

    /** For display — what a merchant is told the commission is. */
    Policy policyFor(String vertical);

    record Policy(String vertical, int percentBps, int fixedMinor) {

        public static Policy none(String vertical) {
            return new Policy(vertical, 0, 0);
        }
    }
}
