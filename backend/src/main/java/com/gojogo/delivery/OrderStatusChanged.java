package com.gojogo.delivery;

import java.util.UUID;

/**
 * Published whenever an order moves along the fulfilment state machine
 * (including cancellation). {@code status} is the wire name the API returns —
 * {@code CONFIRMED}, {@code PREPARING}, {@code COURIER_TO_RESTAURANT},
 * {@code DELIVERING}, {@code DELIVERED}, {@code CANCELLED}.
 *
 * <p>Two of the words it carries are deliberately <em>not</em> order statuses.
 * {@code SUB_CANCELLED} (Phase 4 M3) is one kitchen's slice ending while the
 * rest of the order carries on, and {@code READY_FOR_PICKUP} (Phase 4 M4) is a
 * kitchen saying a collection is on the counter. Both describe a moment the
 * customer needs told about while the order itself has not moved, which is
 * exactly what a seventh and eighth status would have been the wrong way to say
 * — and a consumer that has never heard either drops it in its default arm.
 *
 * <p>Consumed since 2e M3 by {@code notifications}, which turns the three
 * transitions a customer actually wants — the kitchen started, the food is
 * moving, it arrived — plus a cancellation into an APNs push. Settlement is
 * <em>not</em> driven off this event: money is moved inside the same
 * transaction that writes the status, because a push that goes missing is an
 * annoyance and a payment that goes missing is not.
 *
 * @param pickup whether this order is collected in store (Phase 4 M4). The same
 *               six words mean different things to somebody who is walking to a
 *               counter — "on its way" and "tip your courier" are both wrong for
 *               a collection — and carrying the kind is how a push says the
 *               right thing without inventing a parallel set of statuses to say
 *               it with
 */
public record OrderStatusChanged(UUID orderId, UUID userId, String merchantName,
                                 String status, int etaMinutes, boolean pickup) {
}
