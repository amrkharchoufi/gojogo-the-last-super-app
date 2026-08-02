package com.gojogo.delivery.internal;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.UUID;

/**
 * Ends the orders no restaurant ever answered.
 *
 * <p>What is left of {@code OrderFulfilmentJob}, and the inversion is worth
 * stating: that job <em>drove</em> fulfilment, walking every live order to
 * wherever a timeline said it should be. This one drives nothing. Real people
 * move an order now, and the only thing a clock is still entitled to decide is
 * that nobody did.
 *
 * <p>It exists because a simulation could not fail and a kitchen can: an order
 * left in CONFIRMED holds the customer's money in escrow and their one
 * live-order slot with it, and nothing else in the system would ever look at it
 * again. It also collects the rows stranded by this milestone's own deploy —
 * an order in flight when the fulfilment job was deleted has no
 * {@code acceptedAt} either, which is exactly what "nobody ever accepted this"
 * looks like, and it wants the same outcome: cancelled, and the money given
 * back properly through {@code payments} rather than by a migration that cannot
 * move a ledger.
 */
@Component
class OrderTimeoutJob {

    private static final Logger log = LoggerFactory.getLogger(OrderTimeoutJob.class);
    private static final int BATCH = 200;

    private final OrderFulfilmentService fulfilment;

    OrderTimeoutJob(OrderFulfilmentService fulfilment) {
        this.fulfilment = fulfilment;
    }

    @Scheduled(fixedDelayString = "${gojogo.delivery.timeout-poll-ms:60000}")
    void tick() {
        for (UUID orderId : fulfilment.unansweredOrderIds(BATCH)) {
            try {
                fulfilment.timeOut(orderId);
            } catch (OptimisticLockingFailureException anotherInstanceGotThere) {
                // Expected when more than one task runs the poller — the winner's
                // write is the one that counts, and this order is finished either
                // way.
            } catch (RuntimeException e) {
                log.warn("Could not time out delivery order {}: {}", orderId, e.toString());
            }
        }
    }
}
