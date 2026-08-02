package com.gojogo.delivery.internal;

/**
 * How the hunt for a courier is going, kept apart from {@link OrderStatus} on
 * purpose.
 *
 * <p>The temptation is a seventh order status — {@code READY_FOR_PICKUP}, or
 * {@code NO_COURIER}. Both would be wrong. An order status is a stage of the
 * order, the thing the customer's screen and the notification matrix are written
 * against, and every client in the field understands exactly six of them. This
 * is not a stage: it is whether a side quest that runs *underneath* PREPARING
 * has succeeded yet.
 *
 * <p>{@link #FAILED} is the state the simulation could never reach, and the one
 * worth having a word for: dispatch asked everybody within range for the whole
 * request window and nobody took it. The order does not cancel itself over that
 * — the food may already be cooked, and throwing away a made dinner is a
 * decision for the people involved rather than a sweep.
 */
enum CourierSearch {

    /** Nobody has been asked yet — the restaurant hasn't accepted the order. */
    NONE,

    /** Dispatch is working on it, possibly not until nearer the ready time. */
    SEARCHING,

    ASSIGNED,

    /** Every ring searched, nobody took it. */
    FAILED
}
