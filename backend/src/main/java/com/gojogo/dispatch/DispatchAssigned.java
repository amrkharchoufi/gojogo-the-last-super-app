package com.gojogo.dispatch;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Somebody took it. The event the asking vertical waits on — {@code travel}
 * moves the ride to CONFIRMED, {@code delivery} puts a real courier on the order
 * — and the reason dispatch never calls back into either of them by name.
 */
public record DispatchAssigned(UUID jobId, JobKind jobKind, UUID jobRefId,
                               UUID workerId, UUID workerUserId, WorkerKind workerKind,
                               VehicleCategory category, OffsetDateTime assignedAt) {
}
