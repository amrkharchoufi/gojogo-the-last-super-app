package com.gojogo.delivery.internal;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.time.Duration;

/**
 * How long each fulfilment step takes. There is no {@code dispatch} module yet
 * (Phase 3), so nothing real moves an order along — the timeline stands in for
 * a kitchen and a courier, and the job simply follows it.
 *
 * <p>All offsets are measured from the moment the order was placed, so a
 * restart or a missed poll can never leave an order stuck: the correct state is
 * always recomputable from {@code placedAt}.
 */
@Component
class DeliveryTimeline {

    private final Duration preparing;
    private final Duration pickup;
    private final Duration delivering;
    private final Duration delivered;

    DeliveryTimeline(
        @Value("${gojogo.delivery.timeline.preparing-seconds:20}") long preparingSeconds,
        @Value("${gojogo.delivery.timeline.pickup-seconds:75}") long pickupSeconds,
        @Value("${gojogo.delivery.timeline.delivering-seconds:150}") long deliveringSeconds,
        @Value("${gojogo.delivery.timeline.delivered-seconds:330}") long deliveredSeconds) {
        this.preparing = Duration.ofSeconds(preparingSeconds);
        this.pickup = Duration.ofSeconds(pickupSeconds);
        this.delivering = Duration.ofSeconds(deliveringSeconds);
        this.delivered = Duration.ofSeconds(deliveredSeconds);
    }

    /** Where an order placed {@code elapsed} ago should be by now. */
    OrderStatus statusAt(Duration elapsed) {
        if (elapsed.compareTo(delivered) >= 0) {
            return OrderStatus.DELIVERED;
        }
        if (elapsed.compareTo(delivering) >= 0) {
            return OrderStatus.DELIVERING;
        }
        if (elapsed.compareTo(pickup) >= 0) {
            return OrderStatus.COURIER_TO_RESTAURANT;
        }
        if (elapsed.compareTo(preparing) >= 0) {
            return OrderStatus.PREPARING;
        }
        return OrderStatus.CONFIRMED;
    }

    /** Placement → delivery, i.e. the promised ETA. */
    Duration total() {
        return delivered;
    }

    /**
     * How far the courier is along the last leg, 0–1. Used for the moving pin
     * on the tracking map; flat 0 before pickup, 1 once delivered.
     */
    double courierProgress(OrderStatus status, Duration elapsed) {
        if (status == OrderStatus.DELIVERED) {
            return 1;
        }
        if (status != OrderStatus.DELIVERING) {
            return 0;
        }
        double leg = (double) (delivered.toMillis() - delivering.toMillis());
        if (leg <= 0) {
            return 0;
        }
        double done = (elapsed.toMillis() - delivering.toMillis()) / leg;
        return Math.clamp(done, 0d, 1d);
    }
}
