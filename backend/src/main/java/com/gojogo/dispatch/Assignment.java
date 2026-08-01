package com.gojogo.dispatch;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Who is doing it. The answer a vertical gets back, and the only thing dispatch
 * ever tells it about a person.
 *
 * <p>{@code userId} is the profile id, which is how a vertical renders a name, a
 * photo and a badge — through {@code profile}, the module that owns those, and
 * not through a copy dispatch would have to keep fresh.
 *
 * @param workerId       the dispatch registration, for position lookups
 * @param userId         the profile behind it
 * @param rating         out of 5, or 5.0 for somebody nobody has rated yet
 * @param completedCount lifetime completed jobs, which is what "1,204 trips"
 *                       renders from
 */
public record Assignment(UUID workerId, UUID userId, WorkerKind workerKind,
                         VehicleCategory category, JobKind jobKind, UUID jobRefId,
                         double rating, int completedCount, OffsetDateTime assignedAt) {
}
