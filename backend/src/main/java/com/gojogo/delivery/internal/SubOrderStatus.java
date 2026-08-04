package com.gojogo.delivery.internal;

/**
 * One merchant's slice of an order: the order's own states minus the courier
 * ones, which stay on the parent (SPECS §5 — sub-orders carry the prep state
 * machine, the courier is one person and one set of states).
 *
 * <p>{@link #COLLECTED} is the one word of its own. "This kitchen's bag is in
 * the courier's hand" is a fact about one merchant — the parent only moves to
 * DELIVERING when every bag is, and until then a collected sub-order and a
 * cooking one coexist on the same order.
 */
enum SubOrderStatus {

    /** Placed, and waiting for this restaurant to answer. Cancellable by the
     *  customer while it lasts — the kitchen has not started. */
    CONFIRMED,
    /** This restaurant accepted and is cooking. */
    PREPARING,
    /** The courier typed this kitchen's code and has this kitchen's bag. */
    COLLECTED,
    /** The parent order reached the door. Stamped at parent delivery. */
    DELIVERED,
    /** This slice ended early — rejected, timed out, or cancelled by the
     *  customer — and its share of the money went back. */
    CANCELLED;

    /** Still somebody's problem: not delivered, not cancelled. */
    boolean isLive() {
        return this != DELIVERED && this != CANCELLED;
    }
}
