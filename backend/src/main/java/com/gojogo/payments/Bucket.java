package com.gojogo.payments;

/**
 * Which pocket of an owner's money (SPECS.md §1). Buckets are how a single
 * balance stays honest about what it is for: money held for an order in flight
 * is still the customer's, but it is not theirs to spend.
 */
public enum Bucket {

    /** Spendable now. */
    AVAILABLE,

    /** Held for something in flight — an order, a booking. Still the payer's
     *  money: a cancellation releases it rather than refunding it. */
    ESCROW,

    /** Locked. Phase 3's $30 driver stake, which funds verification rewards. */
    STAKING,

    /** Ride-hailing tokens. A ledger credit with a policy price — not a crypto
     *  asset, no chain, nothing to speculate on (ARCHITECTURE §2b decision 2). */
    TOKENS,

    /** Earned rather than bought: Phase 3's community-verification rewards. */
    REWARDS,

    /** Only ever paired with {@link OwnerKind#EXTERNAL}. */
    EXTERNAL
}
