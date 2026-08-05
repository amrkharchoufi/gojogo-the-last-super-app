package com.gojogo.economy.internal;

/**
 * What a digital purchase grants (SPECS §6). {@code SUBSCRIPTION} is in the
 * spec's list and deliberately absent here: it is a Stripe subscription
 * mirrored to an entitlement with an expiry, and no Stripe-subscription path
 * exists in this system yet — an enum constant nothing can issue would only be
 * a word that lies.
 */
enum EntitlementKind {
    /** A re-issuable short-lived signed GET, for as long as the entitlement lives. */
    DOWNLOAD,
    /** A generated key, plus the same download. */
    LICENSE
}
