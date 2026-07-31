package com.gojogo.payments;

/**
 * What a movement <em>was</em>. Not a category for reporting convenience: a
 * capture writes several entries that differ only in kind and payee, and the
 * kinds are what turn them back into a receipt a customer recognises.
 *
 * <p>Kept in step with the CHECK constraint in {@code V23__payments.sql} —
 * adding one means a migration.
 */
public enum LedgerKind {

    /** Card money arriving: EXTERNAL → the payer's AVAILABLE. */
    TOPUP,

    /** AVAILABLE → the same owner's ESCROW, at checkout. */
    HOLD,

    /** ESCROW → AVAILABLE, same owner: the order was cancelled in time. */
    RELEASE,

    /** ESCROW → a payee: the goods half of a settlement. */
    CAPTURE,

    /** The platform's commission on a settlement. */
    FEE,

    /**
     * The delivery fee — the courier's, once couriers exist. Until Phase 4 M1
     * it settles to PLATFORM under this kind rather than being folded into
     * FEE, so that switching the payee later is one line and the history stays
     * readable.
     */
    COURIER_FEE,

    /** 100% to the person who did the work, never split (SPECS §1). */
    TIP,

    /** Money going back, in whole or in part, after a capture. */
    REFUND,

    /** AVAILABLE → EXTERNAL: out to a Stripe Connect account. */
    PAYOUT,

    /** Phase 3: AVAILABLE → STAKING, the driver's $30. */
    STAKE,

    /** Phase 3: STAKING → AVAILABLE, on account closure. */
    STAKE_RELEASE,

    /** Phase 3: buying a token pack. */
    TOKEN_PURCHASE,

    /** Phase 3: a token spent accepting a ride. */
    TOKEN_SPEND,

    /** Phase 3: a community-verification reward, paid from a driver's stake. */
    REWARD,

    /** Anything else moving between two accounts on purpose. */
    TRANSFER,

    /** A correction. The ledger is append-only, so a mistake is another entry
     *  and never an edit — an edited ledger cannot be audited. */
    ADJUSTMENT
}
