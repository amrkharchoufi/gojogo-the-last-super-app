package com.gojogo.delivery.internal;

/**
 * Where a dispute has got to (Phase 4 M6, SPECS §5).
 *
 * <p>Three words and not four: SPECS describes {@code RESOLVED_REFUND(full |
 * partial)}, and full-versus-partial is the <em>amount</em>. A state that
 * duplicates a number is a state that can disagree with it.
 */
enum DisputeState {

    /** Filed, and waiting for a person. Nothing about this escalates on its
     *  own — the queue is somebody's job, exactly like the moderation one. */
    OPEN,

    /** Money went back. How much is on the row; zero is not one of the
     *  outcomes, because a refund of nothing is a rejection. */
    RESOLVED_REFUND,

    /** Looked at, and no. The customer is told, and told why — a dispute that
     *  simply stops being open is one somebody chases forever. */
    RESOLVED_REJECTED;

    boolean isOpen() {
        return this == OPEN;
    }
}
