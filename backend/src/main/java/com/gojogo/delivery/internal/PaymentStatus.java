package com.gojogo.delivery.internal;

/**
 * Where an order's money is. Deliberately separate from {@link OrderStatus}: a
 * delivered order can still be unsettled for a moment, and a cancelled one has
 * money to give back — folding the two into one state machine would make both
 * of those unrepresentable.
 */
enum PaymentStatus {

    /** No money involved. What every order placed before the wallet existed
     *  genuinely is, and what an order is if payments are switched off. */
    UNPAID,

    /** Held in the customer's own ESCROW bucket. Still theirs. */
    HELD,

    /** Split among merchant, courier and platform. Terminal. */
    CAPTURED,

    /** Given back before settlement — the order was cancelled in time. */
    RELEASED,

    /** Given back after settlement. Nothing writes this yet: refunds arrive
     *  with disputes (SPECS §5), which is Phase 4. The state exists so that a
     *  refunded order is not indistinguishable from a released one when it
     *  does. */
    REFUNDED
}
