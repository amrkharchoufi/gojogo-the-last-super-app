package com.gojogo.travel.internal;

import com.gojogo.dispatch.Assignment;
import com.gojogo.dispatch.DispatchApi;
import com.gojogo.dispatch.DispatchAssigned;
import com.gojogo.dispatch.DispatchExhausted;
import com.gojogo.dispatch.JobKind;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * How a ride hears back from dispatch.
 *
 * <p>Events rather than a callback, because dispatch must not know the name of a
 * vertical (ARCHITECTURE §2) — a platform module that did would be edited every
 * time one is added. So dispatch publishes what happened and whoever asked
 * listens; {@code delivery} will hang its courier assignment off the same two
 * events in Phase 4 M1 without dispatch changing at all.
 *
 * <p>Both handlers filter on {@code RIDE} and ignore everything else, which is
 * the whole cost of the arrangement.
 *
 * <p>After commit, like every other listener in this codebase: a ride must not be
 * confirmed off an assignment whose transaction then rolls back.
 */
@Component
class DispatchOutcomeListener {

    private final RideService rides;
    private final DispatchApi dispatch;

    DispatchOutcomeListener(RideService rides, DispatchApi dispatch) {
        this.rides = rides;
        this.dispatch = dispatch;
    }

    /**
     * A driver accepted — at the rider's asking price, since a driver who wanted
     * a different one would have countered instead and the ride would have been
     * confirmed through {@code RideService} directly.
     *
     * <p>Re-reads the assignment rather than trusting the event's fields for the
     * vehicle: the event says who, and the assignment says what they are driving.
     */
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onAssigned(DispatchAssigned event) {
        if (event.jobKind() != JobKind.RIDE) return;
        Assignment assignment = dispatch.assignmentFor(JobKind.RIDE, event.jobRefId())
            .orElse(null);
        if (assignment == null) return;
        rides.confirmFromDispatch(event.jobRefId(), assignment);
    }

    /** Every ring searched and nobody took it. */
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onExhausted(DispatchExhausted event) {
        if (event.jobKind() != JobKind.RIDE) return;
        rides.exhaust(event.jobRefId());
    }
}
