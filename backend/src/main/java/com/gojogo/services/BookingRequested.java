package com.gojogo.services;

import java.time.OffsetDateTime;
import java.util.UUID;

/** A booking landed in a provider's queue. Carries the owner id so
 *  notifications can push without a read into this module. */
public record BookingRequested(UUID bookingId, UUID providerOwnerId, String serviceName,
                               OffsetDateTime startsAt) {
}
