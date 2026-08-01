package com.gojogo.partner.internal;

/**
 * Where a vehicle's claim stands.
 *
 * <p>{@code APPROVED} and {@code COMMUNITY_VERIFIED} are both "this car may
 * work" — the second is Phase 3 M5's passenger confirmation, which earns a badge
 * rather than a permission. Keeping them as separate states rather than a
 * boolean on top of one is what lets the badge exist before the mechanism does.
 */
enum VehicleState {

    SUBMITTED,
    APPROVED,
    COMMUNITY_VERIFIED,
    /** Papers lapsed, or a passenger said the car doesn't match. Not a
     *  rejection — a re-upload can clear it. */
    FLAGGED,
    RETIRED;

    /** Whether dispatch may send work in this vehicle. */
    boolean isRoadworthy() {
        return this == APPROVED || this == COMMUNITY_VERIFIED;
    }

    /** Whether a reviewer still has to look at it. */
    boolean isPending() {
        return this == SUBMITTED;
    }
}
