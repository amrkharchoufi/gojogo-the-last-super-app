package com.gojogo.delivery.internal;

/**
 * Fulfilment state machine. The order of the constants is the order of the
 * happy path — {@link #CANCELLED} sits outside it and is terminal.
 */
enum OrderStatus {
    CONFIRMED,
    PREPARING,
    COURIER_TO_RESTAURANT,
    DELIVERING,
    DELIVERED,
    CANCELLED;

    boolean isTerminal() {
        return this == DELIVERED || this == CANCELLED;
    }

    /** Next step on the happy path, or empty at the end of it. */
    java.util.Optional<OrderStatus> next() {
        return switch (this) {
            case CONFIRMED -> java.util.Optional.of(PREPARING);
            case PREPARING -> java.util.Optional.of(COURIER_TO_RESTAURANT);
            case COURIER_TO_RESTAURANT -> java.util.Optional.of(DELIVERING);
            case DELIVERING -> java.util.Optional.of(DELIVERED);
            case DELIVERED, CANCELLED -> java.util.Optional.empty();
        };
    }
}
