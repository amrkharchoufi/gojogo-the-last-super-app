package com.gojogo.payments;

/**
 * Who an account belongs to.
 *
 * <p>A pair of (kind, id) rather than a user column, because the payees this
 * platform will have are not all people: a merchant is owed the food half of an
 * order while its owner is owed nothing personally, and Phase 3's drivers and
 * Phase 5's providers arrive the same way.
 */
public enum OwnerKind {

    /** A person, by {@code profile.user_profile} id. */
    USER,

    /** A provisioned merchant, by the vertical's merchant id. */
    MERCHANT,

    /** GojoGo itself — commissions, service fees, and money held on behalf of
     *  actors that do not exist yet (couriers, until Phase 4 M1). Singleton. */
    PLATFORM,

    /**
     * The world outside, on the far side of Stripe. Singleton, and the only
     * account allowed a negative balance: it is the counterparty for every
     * top-up, so money arriving from a card has to come from <em>somewhere</em>
     * for the entries to balance. Its balance, negated, is how much real money
     * the platform has taken in net of payouts.
     */
    EXTERNAL
}
