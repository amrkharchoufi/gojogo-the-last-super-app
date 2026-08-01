package com.gojogo.dispatch;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * A job has been put in front of one worker. Consumed by {@code notifications},
 * which turns it into the push that makes a phone in a pocket worth carrying —
 * an offer nobody is told about expires in thirty seconds having achieved
 * nothing.
 *
 * <p>No activity row: an offer is not something to read about later, and by the
 * time anybody scrolled to it the work would be gone.
 */
public record DispatchOffered(UUID jobId, UUID offerId, JobKind jobKind, UUID jobRefId,
                              UUID workerId, UUID workerUserId, String pickupLabel,
                              OffsetDateTime expiresAt) {
}
