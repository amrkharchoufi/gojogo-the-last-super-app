package com.gojogo.economy.internal;

/**
 * Where a product order is. Four words — see {@code ProductOrder} for why there
 * is no in-transit choreography between them.
 */
enum ProductOrderStatus {
    /** Paid (held) and waiting for the seller to post it. The only state a
     *  cancellation is allowed from — after that somebody's parcel is moving. */
    PLACED,
    SHIPPED,
    /** Received (or presumed received by the auto-complete sweep); the money
     *  has moved to the seller. Terminal. */
    COMPLETED,
    /** Ended before shipping; the hold went back and the stock came back.
     *  Terminal. */
    CANCELLED
}
