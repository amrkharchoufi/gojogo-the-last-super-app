package com.gojogo.delivery.internal;

/**
 * Whose money a dispute refund comes out of (Phase 4 M6).
 *
 * <p><b>Three payers rather than one, because settlement already split the
 * money three ways.</b> By the time anybody disputes an order it has been
 * captured: the kitchen has its food value less commission, the courier has the
 * delivery fee and the tip, and the platform has the commission and the service
 * fee. There is no pot left to refund <em>from</em> — a refund is money coming
 * back off somebody who has already been paid, so the only question that can be
 * answered is which of the three.
 *
 * <p><b>Every payer is capped at what they actually received for this order.</b>
 * Not because the ledger would refuse a larger debit — a merchant's balance
 * carries other orders' money — but because taking one order's dispute out of
 * another order's earnings is how a restaurant discovers a refund it was never
 * shown. The cap is what makes a refund arguable from the entries, which is what
 * {@code WalletApi.entriesFor} was written for.
 *
 * <p><b>And none of them can go below zero.</b> Only EXTERNAL accounts allow a
 * negative balance, so a merchant who has already paid out cannot fund a refund
 * at all — that is a refusal naming the number, not a silent fallback to the
 * platform. Somebody has to decide who absorbs it, and quietly deciding on their
 * behalf is how the platform ends up paying for every restaurant's mistakes
 * without anybody choosing that.
 */
enum DisputePayer {

    /** The kitchen whose slice this is. Requires the dispute to name a
     *  sub-order: "the merchant pays" is not an instruction on an order that
     *  spans three of them. */
    MERCHANT,

    /** Whoever carried it. Capped at the delivery fees and the tip, and
     *  unavailable on a collection, where there was no courier. */
    COURIER,

    /** The platform's own take — commission plus the service fee. The payer of
     *  last resort, and the only one that is always available. */
    PLATFORM;

    static DisputePayer parse(String raw, DisputePayer fallback) {
        if (raw == null || raw.isBlank()) return fallback;
        try {
            return valueOf(raw.trim().toUpperCase());
        } catch (IllegalArgumentException notAPayer) {
            return fallback;
        }
    }
}
