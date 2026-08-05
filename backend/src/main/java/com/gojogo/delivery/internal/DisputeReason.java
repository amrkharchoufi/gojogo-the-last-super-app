package com.gojogo.delivery.internal;

/**
 * What went wrong with a delivered order (Phase 4 M6, SPECS §5).
 *
 * <p>A closed list rather than free text, because the reason is what suggests
 * <em>who pays</em>: food that never arrived in the bag is the kitchen's, food
 * that arrived at the wrong door is the courier's. The suggestion is only ever a
 * default — the operator names the payer — but a free-text reason would make
 * even the default impossible.
 *
 * <p>The customer's own words go in the note beside this. The list exists to be
 * sorted and counted; the note is what is actually read.
 */
enum DisputeReason {

    /** Some of it is missing. The most common one, and the one the itemised
     *  claim exists for. */
    MISSING_ITEMS(DisputePayer.MERCHANT),

    /** Somebody else's order, or the wrong version of theirs. */
    WRONG_ITEMS(DisputePayer.MERCHANT),

    /** It arrived in a state nobody would eat. Suggests the kitchen, because a
     *  bag that survives the kitchen usually survives the bike — and because
     *  the alternative charges a courier for a leaking container. */
    DAMAGED(DisputePayer.MERCHANT),

    /** Marked delivered and nobody got it. The one reason that is about the
     *  journey rather than the food. */
    NEVER_ARRIVED(DisputePayer.COURIER),

    /** Everything else, and the reason the note field is not optional. No
     *  suggested payer at all: an operator who has to read it is exactly who
     *  should be deciding. */
    OTHER(DisputePayer.PLATFORM);

    private final DisputePayer suggestedPayer;

    DisputeReason(DisputePayer suggestedPayer) {
        this.suggestedPayer = suggestedPayer;
    }

    /** Where the money would come from if the operator agrees. A default on the
     *  admin screen, never a decision. */
    DisputePayer suggestedPayer() {
        return suggestedPayer;
    }

    static DisputeReason parse(String raw) {
        if (raw == null || raw.isBlank()) return OTHER;
        try {
            return valueOf(raw.trim().toUpperCase());
        } catch (IllegalArgumentException notAReason) {
            return OTHER;
        }
    }
}
