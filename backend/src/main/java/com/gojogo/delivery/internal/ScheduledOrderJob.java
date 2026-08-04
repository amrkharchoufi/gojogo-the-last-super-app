package com.gojogo.delivery.internal;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.UUID;

/**
 * Puts scheduled orders in front of their kitchens when the time comes
 * (Phase 4 M5).
 *
 * <p>Deliberately separate from {@link OrderTimeoutJob} even though both are a
 * clock over the same table, because they are opposite kinds of thing. That one
 * decides that <em>nobody did anything</em> — the last remaining thing a clock
 * is entitled to conclude in this vertical, and the whole of what survived the
 * simulated fulfilment job. This one carries out an instruction a person gave:
 * the customer said eight o'clock, and this is the eight o'clock. Folding them
 * together would make one class whose job is "things that happen on a timer",
 * which is a category and not a responsibility.
 *
 * <p>It is also the only mechanism this milestone needed. A scheduled order is
 * not a new state machine — it is the existing one, started later, and the
 * courier search still schedules itself off {@code DispatchRequest.startAfter}
 * exactly as it has since Phase 4 M1.
 */
@Component
class ScheduledOrderJob {

    private static final Logger log = LoggerFactory.getLogger(ScheduledOrderJob.class);
    private static final int BATCH = 200;

    private final OrderFulfilmentService fulfilment;

    ScheduledOrderJob(OrderFulfilmentService fulfilment) {
        this.fulfilment = fulfilment;
    }

    /**
     * Polls on the half-minute. The margin that matters is already built into
     * the promotion time — the kitchens get their whole answering window plus
     * the slowest one's own advertised time — so a promotion that lands twenty
     * seconds late costs nothing, and a tighter poll would be a query a minute
     * for the rest of the platform's life to buy that.
     */
    @Scheduled(fixedDelayString = "${gojogo.delivery.schedule-poll-ms:30000}")
    void tick() {
        for (UUID orderId : fulfilment.dueForQueueIds(BATCH)) {
            try {
                fulfilment.promote(orderId);
            } catch (OptimisticLockingFailureException anotherInstanceGotThere) {
                // Expected when more than one task runs the poller. The winner
                // stamped the order queued; the loser's promotion would have
                // been the same one, and a second announcement is exactly what
                // the stamp exists to prevent.
            } catch (RuntimeException e) {
                // Left unqueued on purpose, so the next tick tries again: an
                // order that never reaches a kitchen is a dinner that does not
                // happen, and the accept timeout only starts once it does.
                log.warn("Could not promote scheduled order {}: {}", orderId, e.toString());
            }
        }
    }
}
