package com.gojogo.dispatch;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Where somebody was when they last said. {@code at} is part of the answer, not
 * metadata: a position with no age is a position a caller will draw on a map as
 * though it were now, and a phone in a tunnel is indistinguishable from one
 * parked outside.
 */
public record WorkerPosition(UUID workerId, UUID userId,
                             double latitude, double longitude, OffsetDateTime at) {
}
