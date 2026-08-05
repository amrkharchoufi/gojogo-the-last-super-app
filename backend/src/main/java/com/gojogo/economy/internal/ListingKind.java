package com.gojogo.economy.internal;

/**
 * What kind of sale a listing is. {@code STANDARD} is the original C2C shape —
 * chat, meet, pay however you like. {@code OWNERSHIP_TRANSFER} (Phase 5 M2) is
 * for the numbered things — a car, a registered instrument — where the money
 * waits in escrow until a human has looked at the paperwork.
 */
enum ListingKind {
    STANDARD,
    OWNERSHIP_TRANSFER;

    static ListingKind parse(String value) {
        if (value == null || value.isBlank()) return STANDARD;
        try {
            return valueOf(value.trim().toUpperCase());
        } catch (IllegalArgumentException unknown) {
            return STANDARD;
        }
    }
}
