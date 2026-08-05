package com.gojogo.economy.internal;

/**
 * Where an ownership transfer is (SPECS §6). Cancellation is open through
 * {@code PAYMENT_HELD} and closed from {@code DOCS_CONFIRMED} on — once a human
 * has confirmed the paperwork, the handover is presumed happening.
 */
enum TransferState {
    INQUIRY,
    OFFER_ACCEPTED,
    PAYMENT_HELD,
    DOCS_CONFIRMED,
    TRANSFERRED,
    /** The money reached the seller. Terminal. */
    RELEASED,
    /** Terminal; anything held went back to the buyer in full. */
    CANCELLED;

    boolean cancellable() {
        return this == INQUIRY || this == OFFER_ACCEPTED || this == PAYMENT_HELD;
    }
}
