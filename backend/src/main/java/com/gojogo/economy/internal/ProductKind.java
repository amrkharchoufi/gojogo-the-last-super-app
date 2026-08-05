package com.gojogo.economy.internal;

/**
 * What buying this actually delivers. {@code PHYSICAL} ships; {@code DIGITAL}
 * (Phase 5 M2) grants an entitlement and never sees a courier or a shipping
 * fee. A kind, not a subclass — the same modelling call as delivery's
 * {@code FulfilmentKind}, and for the same reason: one branch at the few places
 * the difference is real beats a parallel type hierarchy.
 */
enum ProductKind {
    PHYSICAL,
    DIGITAL
}
