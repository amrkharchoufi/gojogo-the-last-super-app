package com.gojogo.delivery;

import java.util.UUID;

/**
 * Published whenever an order moves along the fulfilment state machine
 * (including cancellation). {@code status} is the wire name the API returns —
 * {@code CONFIRMED}, {@code PREPARING}, {@code COURIER_TO_RESTAURANT},
 * {@code DELIVERING}, {@code DELIVERED}, {@code CANCELLED}.
 *
 * <p>No consumer yet; this is the hook an APNs "your food is on the way" push
 * hangs off (the {@code notifications} module already consumes
 * {@code messaging.MessageSent} the same way).
 */
public record OrderStatusChanged(UUID orderId, UUID userId, String merchantName,
                                 String status, int etaMinutes) {
}
