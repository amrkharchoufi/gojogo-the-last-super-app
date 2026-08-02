package com.gojogo.delivery.internal;

import com.gojogo.dispatch.Assignment;
import com.gojogo.dispatch.DispatchApi;
import com.gojogo.dispatch.DispatchAssigned;
import com.gojogo.dispatch.DispatchExhausted;
import com.gojogo.dispatch.JobKind;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * How an order hears back from dispatch — and the second implementation of a
 * shape {@code travel} predicted exactly: <i>"delivery will hang its courier
 * assignment off the same two events in Phase 4 M1 without dispatch changing at
 * all"</i>. It did, and dispatch did not change: not a line, not a constant, not
 * a new verb. That is the whole return on events rather than callbacks.
 *
 * <p>Both handlers filter on {@code DELIVERY} and ignore everything else, which
 * is the entire cost of the arrangement.
 *
 * <p>After commit, like every other listener here: an order must not get a
 * courier off an assignment whose transaction then rolls back.
 */
@Component
class CourierDispatchListener {

    private final OrderFulfilmentService fulfilment;
    private final DispatchApi dispatch;

    CourierDispatchListener(OrderFulfilmentService fulfilment, DispatchApi dispatch) {
        this.fulfilment = fulfilment;
        this.dispatch = dispatch;
    }

    /**
     * A courier accepted. There is no negotiation on a delivery — the fee is what
     * the customer already paid — so unlike a ride this is the only way an order
     * ever gets one.
     *
     * <p>Re-reads the assignment rather than trusting the event's fields: the
     * event says who, and the assignment says what they are riding and how many
     * deliveries they have behind them, which is what the customer sees.
     */
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onAssigned(DispatchAssigned event) {
        if (event.jobKind() != JobKind.DELIVERY) return;
        Assignment assignment = dispatch.assignmentFor(JobKind.DELIVERY, event.jobRefId())
            .orElse(null);
        if (assignment == null) return;
        fulfilment.courierAssigned(event.jobRefId(), assignment);
    }

    /** Every ring searched and nobody took it. */
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onExhausted(DispatchExhausted event) {
        if (event.jobKind() != JobKind.DELIVERY) return;
        fulfilment.courierSearchFailed(event.jobRefId());
    }
}
