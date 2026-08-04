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
 * <p>Since Phase 4 M3 an order can span merchants, so one event is published
 * <b>per kitchen</b>: each owner is told about their slice and only their
 * slice, and {@code totalCents} is that slice's food value after its own
 * discount rather than the whole checkout.
 *
 * <p><b>Since Phase 4 M5 it is published when the kitchen is told, which for a
 * scheduled order is not when the customer placed it.</b> That follows from
 * what the event is for: it exists to put an order in front of a person, and a
 * push at noon about an eight o'clock dinner is a push somebody will have
 * forgotten by the time it matters. {@code placedAt} still means what it says —
 * when the customer ordered — so a consumer that needs "how long has this been
 * in front of me" must not read it as that.
 *
 * @param merchantOwnerId the profile that manages the restaurant, i.e. the phone
 *                        that should light up
 */
public record OrderPlaced(UUID orderId, UUID userId, UUID merchantId, String merchantName,
                          UUID merchantOwnerId, long totalCents, String currency,
                          OffsetDateTime placedAt) {
}
