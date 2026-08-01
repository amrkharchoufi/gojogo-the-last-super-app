package com.gojogo.payments;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * A driver just spent a token and is nearly out (SPECS §4's low-balance push,
 * §12's coverage matrix).
 *
 * <p>Published at the moment of the spend rather than by a sweep, because that
 * is the only moment the system reliably knows: a balance that has been sitting
 * at one token for a week is not news, and a nightly job that told everybody
 * about it would be. Consumed by {@code notifications}.
 *
 * <p>Carries the count, not the money. A token balance is the number the driver
 * acts on, and a push saying "$3.00 of tokens left" is asking somebody to do
 * arithmetic on a lock screen.
 *
 * @param remainingTokens what is left after the spend — zero is the important
 *                        case, because from here they stop being offered work
 * @param threshold       the policy value that made this worth sending, so the
 *                        wording can say "fewer than N" without a second read
 */
public record TokensRanOut(UUID profileId, long remainingTokens, long threshold,
                           OffsetDateTime at) {

    /** Nothing left at all — the case where the driver has stopped receiving
     *  offers rather than merely being warned. */
    public boolean isEmpty() {
        return remainingTokens <= 0;
    }
}
