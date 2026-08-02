package com.gojogo.delivery;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Published in-process when a customer places a delivery order.
 *
 * <p>Consumed since Phase 4 M1 by {@code notifications}, which tells the
 * restaurant. That is what {@code merchantOwnerId} is for and why it was added:
 * until real couriers, an order needed nobody's attention — a simulated timeline
 * started cooking on its own — and a kitchen that is never told has an order it
 * can only time out. The owner's profile id is a fact {@code delivery} holds
 * (it is the stamp {@code partner} left at provisioning), and passing it here is
 * cheaper than a consumer that would have to read across for it.
 *
 * @param merchantOwnerId the profile that manages the restaurant, i.e. the phone
 *                        that should light up
 */
public record OrderPlaced(UUID orderId, UUID userId, UUID merchantId, String merchantName,
                          UUID merchantOwnerId, long totalCents, String currency,
                          OffsetDateTime placedAt) {
}
