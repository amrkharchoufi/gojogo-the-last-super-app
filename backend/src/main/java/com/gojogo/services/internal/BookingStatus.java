package com.gojogo.services.internal;

/** SPECS §7's booking words, all seven, exactly as written. */
enum BookingStatus {
    REQUESTED,
    CONFIRMED,
    COMPLETED,
    DECLINED,
    CANCELLED_CUSTOMER,
    CANCELLED_PROVIDER,
    NO_SHOW;

    /** Still occupying its slot on the calendar. */
    boolean occupiesSlot() {
        return this == REQUESTED || this == CONFIRMED;
    }
}
