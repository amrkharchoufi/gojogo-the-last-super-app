package com.gojogo.delivery;

import java.util.UUID;

/**
 * Published whenever an order moves along the fulfilment state machine
 * (including cancellation). {@code status} is the wire name the API returns —
 * {@code CONFIRMED}, {@code PREPARING}, {@code COURIER_TO_RESTAURANT},
 * {@code DELIVERING}, {@code DELIVERED}, {@code CANCELLED}.
 *
 * <p>Consumed since 2e M3 by {@code notifications}, which turns the three
 * transitions a customer actually wants — the kitchen started, the food is
 * moving, it arrived — plus a cancellation into an APNs push. Settlement is
 * <em>not</em> driven off this event: money is moved inside the same
 * transaction that writes the status, because a push that goes missing is an
 * annoyance and a payment that goes missing is not.
 */
public record OrderStatusChanged(UUID orderId, UUID userId, String merchantName,
                                 String status, int etaMinutes) {
}
