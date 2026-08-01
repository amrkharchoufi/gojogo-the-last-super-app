package com.gojogo.travel;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * A trip finished and was paid for.
 *
 * <p>Two consumers are waiting on this by name. {@code notifications} turns it
 * into a receipt push, and {@code partner} (Phase 3 M5) uses the *first* one for
 * an APPROVED-but-unverified vehicle to invite that passenger to confirm the car
 * matches — which is why {@code vehicleId} is on the event rather than left for a
 * consumer to look up.
 *
 * @param fareMinor what was actually paid, not what was quoted
 */
public record TripCompleted(UUID rideId, UUID riderId, UUID driverUserId, UUID driverWorkerId,
                            UUID vehicleId, long fareMinor, String currency,
                            OffsetDateTime completedAt) {
}
