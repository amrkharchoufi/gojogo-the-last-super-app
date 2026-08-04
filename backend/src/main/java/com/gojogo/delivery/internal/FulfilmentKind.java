package com.gojogo.delivery.internal;

/**
 * How an order gets from the kitchen to the person who ordered it (Phase 4 M4,
 * SPECS §5).
 *
 * <p><b>A kind and not a flag on the courier.</b> Collection was missing from
 * this vertical entirely — the vision, the plan and the storefront's {@code
 * info} block all assumed it existed — and the tempting way to add it is a
 * delivery whose courier happens to be nobody. That is the wrong shape: it puts
 * a null courier into every screen, a zero fee into every receipt and a job
 * nobody wants into dispatch, and every one of those has to be special-cased
 * anyway. A kind is one branch, taken once, at the three places it means
 * something: pricing, the courier search, and who types the handoff code.
 *
 * <p><b>It belongs to the order, not to the sub-order</b>, which is the one
 * place this milestone departs from what M3 predicted. Per-merchant reads well
 * until the money is followed: a mixed order needs a courier for some bags and
 * not others, and then has to decide whether it is finished when the courier is
 * done or when the customer eventually walks to the other counter — with one
 * hold, one settlement and one terminal moment to answer that with. A checkout
 * is one kind, and a customer who wants both is told to place two orders rather
 * than being handed an order that is half-arrived forever.
 */
enum FulfilmentKind {

    /** A courier collects it and brings it to an address. Everything Phase 4
     *  M1–M3 built, and what every order that predates this milestone is. */
    DELIVERY,

    /** The customer collects it at the counter. No dispatch, no courier, no
     *  delivery fee, no tip, no address. */
    PICKUP;

    boolean isPickup() {
        return this == PICKUP;
    }

    /**
     * The word a client sent, or {@link #DELIVERY} for anything else.
     *
     * <p>Never a 400, for the same reason {@code HandoffMode.parse} isn't:
     * checkout is the worst place in the product to fail on a string. Falling
     * back to DELIVERY specifically — rather than to a configured default — is
     * because the fallback has to be the kind that works everywhere, and a
     * merchant who has not enabled collection would refuse a PICKUP anyway.
     */
    static FulfilmentKind parse(String raw) {
        if (raw == null || raw.isBlank()) return DELIVERY;
        try {
            return valueOf(raw.trim().toUpperCase());
        } catch (IllegalArgumentException notAKind) {
            return DELIVERY;
        }
    }
}
