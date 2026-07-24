package com.gojogo.delivery.internal;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.UUID;

/**
 * Moves live orders along the fulfilment timeline. This is the stand-in for the
 * platform {@code dispatch} module (Phase 3): when a real courier network
 * exists, this class is what it replaces — the state machine, the events and
 * the API all stay as they are.
 *
 * <p>Every tick recomputes each order's correct state from its placement time,
 * so a missed run, a restart, or a slow deploy catches up instead of leaving
 * someone's dinner stuck in "Preparing" forever.
 */
@Component
class OrderFulfilmentJob {

    private static final Logger log = LoggerFactory.getLogger(OrderFulfilmentJob.class);
    private static final int BATCH = 200;

    private final DeliveryService delivery;

    OrderFulfilmentJob(DeliveryService delivery) {
        this.delivery = delivery;
    }

    @Scheduled(fixedDelayString = "${gojogo.delivery.fulfilment-poll-ms:10000}")
    void tick() {
        for (UUID orderId : delivery.openOrderIds(BATCH)) {
            try {
                delivery.advance(orderId);
            } catch (OptimisticLockingFailureException anotherInstanceGotThere) {
                // Expected when more than one task runs the poller — skip; the
                // next tick reads whatever the winner wrote.
            } catch (RuntimeException e) {
                log.warn("Delivery fulfilment failed for order {}: {}", orderId, e.toString());
            }
        }
    }
}
