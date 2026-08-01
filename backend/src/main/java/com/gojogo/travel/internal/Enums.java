package com.gojogo.travel.internal;

/**
 * Where a ride is. {@code DRAFT} from SPECS §2 is deliberately absent — a ride
 * nobody has requested is a screen in the app, not a row in a table.
 */
enum RideState {

    /** Dispatch is asking drivers, at the rider's price. */
    REQUESTED,
    /** At least one driver has countered; the rider is choosing. */
    NEGOTIATING,
    /** Matched and priced. The fare is frozen from here. */
    CONFIRMED,
    /** The driver is on their way to the pickup. */
    ARRIVING,
    IN_TRIP,
    COMPLETED,
    CANCELLED_RIDER,
    CANCELLED_DRIVER,
    /** Nobody took it in time. */
    EXPIRED;

    /** Still looking for somebody — the only states an offer may be made in. */
    boolean isOpen() {
        return this == REQUESTED || this == NEGOTIATING;
    }

    /** Matched, and not yet over. */
    boolean isLive() {
        return this == CONFIRMED || this == ARRIVING || this == IN_TRIP;
    }

    boolean isFinished() {
        return this == COMPLETED || this == CANCELLED_RIDER
            || this == CANCELLED_DRIVER || this == EXPIRED;
    }
}

/**
 * Who made an offer — which is what decides who may accept it. A driver cannot
 * accept their own counter, and neither can a rider.
 */
enum OfferParty {

    RIDER,
    DRIVER
}

/**
 * What became of one counteroffer.
 *
 * <p>{@code WITHDRAWN} is what every other driver's counter becomes the moment
 * one is accepted — the same distinction dispatch draws between losing a race and
 * ignoring your phone, and kept for the same reason.
 */
enum RideOfferState {

    PENDING,
    ACCEPTED,
    DECLINED,
    EXPIRED,
    WITHDRAWN;

    boolean isOpen() {
        return this == PENDING;
    }
}
