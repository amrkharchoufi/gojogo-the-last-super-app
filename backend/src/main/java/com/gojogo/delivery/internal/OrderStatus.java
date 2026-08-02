package com.gojogo.delivery.internal;

/**
 * Fulfilment state machine. The order of the constants is the order of the
 * happy path — {@link #CANCELLED} sits outside it and is terminal.
 *
 * <p><b>Unchanged by Phase 4 M1, and that is the headline.</b> These six words
 * were written against a simulated fulfilment and are the whole vocabulary every
 * client, both domain events and the notification matrix are built on; replacing
 * the simulation with real people changed <em>who causes</em> each transition
 * and not one of the transitions themselves. Two states a real fulfilment could
 * have added and deliberately did not: "the food is ready" (a timestamp — the
 * customer's dinner is still coming, and their screen should still say so) and
 * "nobody took the delivery" ({@link CourierSearch} — a problem <em>with</em> an
 * order rather than a stage <em>of</em> one).
 *
 * <p>There is no {@code next()} any more. Under the timeline there had to be,
 * because a job walked an order forward a step at a time; now every transition
 * has an actor who names the state they are moving it to, and a method
 * answering "what comes next" would be a second, quieter definition of the same
 * machine.
 */
enum OrderStatus {

    /** Placed, and waiting for the restaurant to answer. */
    CONFIRMED,
    /** The restaurant accepted; a courier is being looked for. */
    PREPARING,
    /** A courier took the job and is on their way to collect it. */
    COURIER_TO_RESTAURANT,
    /** They have the food. From here the customer can no longer cancel. */
    DELIVERING,
    DELIVERED,
    CANCELLED;

    boolean isTerminal() {
        return this == DELIVERED || this == CANCELLED;
    }
}
