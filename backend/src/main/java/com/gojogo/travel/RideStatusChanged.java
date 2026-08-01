package com.gojogo.travel;

import java.util.UUID;

/**
 * Published on every move through the ride state machine, for the same reason
 * {@code delivery.OrderStatusChanged} is: the person waiting on a kerb is not
 * looking at their phone, and a push is the only thing that reaches them.
 *
 * <p>{@code status} is the wire name the API returns, so a consumer never has to
 * know this module's internal enum.
 *
 * @param recipientId who the change is *about* — the rider for most transitions,
 *                    the driver for a rider's cancellation. Named rather than
 *                    inferred, because a consumer guessing wrong sends somebody
 *                    else's news to the wrong phone
 */
public record RideStatusChanged(UUID rideId, UUID recipientId, String status,
                                String otherPartyName, long fareMinor, String currency) {
}
