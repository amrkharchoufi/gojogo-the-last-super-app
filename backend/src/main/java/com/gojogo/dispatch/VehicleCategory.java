package com.gojogo.dispatch;

/**
 * What a worker is driving, and therefore what they can be sent.
 *
 * <p>Named by vehicle rather than by service class ("economy", "comfort") on
 * purpose: a category has to mean the same thing to a rider asking for a big car
 * and to a restaurant asking for anything that can carry a pizza, and only the
 * vehicle is common to both. A request names the <em>set</em> it will accept, so
 * a small basket can say "bike or scooter or car" in one query.
 */
public enum VehicleCategory {

    BIKE,
    SCOOTER,
    CAR,
    /** A larger or newer car — the ride tier a rider pays more for. */
    COMFORT,
    /** Six seats or more. */
    XL,
    /** Courier-side bulk: furniture, a weekly shop. */
    VAN;

    /** What an approval provisions before Phase 3 M2 registers a real vehicle. */
    public static VehicleCategory defaultFor(WorkerKind kind) {
        return kind == WorkerKind.DRIVER ? CAR : BIKE;
    }
}
