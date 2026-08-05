package com.gojogo.services;

import java.time.OffsetDateTime;
import java.util.UUID;

/** The SPECS §12 reminder — fired at roughly 24 hours and again at 1 hour
 *  before a confirmed appointment. */
public record BookingReminder(UUID bookingId, UUID customerId, String serviceName,
                              OffsetDateTime startsAt, int hoursAhead) {
}
