package com.gojogo.dispatch;

/**
 * Which registry a request searches. The same person may hold both — the
 * vision's "switch between roles" is two rows, not a mode flag — and an accepted
 * job in either makes them busy in both, because there is only one of them.
 */
public enum WorkerKind {

    /** Ride-hailing, for the {@code travel} vertical (Phase 3 M3). */
    DRIVER,
    /** Delivery, for {@code delivery}'s orders (Phase 4 M1). */
    COURIER
}
