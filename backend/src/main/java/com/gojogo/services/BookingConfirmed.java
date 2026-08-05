package com.gojogo.services;

import java.time.OffsetDateTime;
import java.util.UUID;

/** The provider (or an accepted quote) confirmed the appointment. */
public record BookingConfirmed(UUID bookingId, UUID customerId, String serviceName,
                               OffsetDateTime startsAt) {
}
