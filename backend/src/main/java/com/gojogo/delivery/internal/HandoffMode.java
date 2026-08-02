package com.gojogo.delivery.internal;

/**
 * How the food gets from the courier's hands to the customer's.
 *
 * <p>A property of the <em>order</em> rather than of the account, because it is
 * a decision people make per delivery and often late: "leave it at the door" is
 * what somebody types when the courier is four minutes away and the baby has
 * just gone down. So it is set at checkout, changeable in flight, and read at
 * the moment of the handoff rather than snapshotted at assignment.
 *
 * <p>Deliberately not an order status. A delivery being handed over by photo
 * rather than by PIN is not a different stage of an order — the six words are
 * untouched (M1's rule, and M2 keeps it) and this is one column beside them.
 */
enum HandoffMode {

    /** The customer reads out a six-digit PIN. The default, because it is the
     *  one that proves the food reached the person who ordered it. */
    PIN,

    /** Contactless: the courier photographs the drop-off instead. The photo is
     *  the evidence the PIN would have been. */
    PHOTO,

    /** A plain tap. What every order did before this milestone, and what every
     *  order that predates it still does. */
    CONFIRM;

    /**
     * Reads a client's word, falling back rather than refusing.
     *
     * <p>An unrecognised value is the configured default and not a 400, and
     * that is a product decision rather than laziness: this arrives on a
     * checkout body and on a one-tap control, and an order that cannot be
     * placed because an older build sent a word this one has never heard of is
     * a failure the customer can neither understand nor fix.
     */
    static HandoffMode parse(String raw, HandoffMode fallback) {
        if (raw == null || raw.isBlank()) return fallback;
        try {
            return valueOf(raw.trim().toUpperCase());
        } catch (IllegalArgumentException notAMode) {
            return fallback;
        }
    }
}
