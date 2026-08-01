package com.gojogo.dispatch.internal;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/**
 * Everything a worker's app needs in one call — registrations, whatever is on
 * screen right now, and the job they are already on.
 *
 * @param positionIntervalSeconds how often to report a position while available.
 *                                Told by the server rather than compiled into
 *                                the app, because the cost of it is the server's
 *                                problem and changing it should not be a release
 */
record MyDispatchResponse(List<WorkerDto> workers, List<OfferDto> offers,
                          AssignmentDto assignment, long positionIntervalSeconds) {
}

/**
 * One registration.
 *
 * @param status    OFFLINE | AVAILABLE | BUSY
 * @param suspended the platform's switch, reported separately from {@code status}
 *                  so the app can explain why going available is refused
 */
record WorkerDto(UUID id, String kind, String category, String status, boolean suspended,
                 String homeRegion, double rating, int ratingCount,
                 int completedCount, int cancelledCount,
                 Double latitude, Double longitude, OffsetDateTime positionAt,
                 WorkerPerformance last30Days) {
}

/**
 * The rolling window SPECS §3 asks for, computed from offer rows rather than
 * stored — a counter that can drift from the rows it summarises will.
 *
 * @param acceptanceRate percent, or null when nothing has been offered yet. Null
 *                       rather than zero: "0%" on a first day reads as an
 *                       accusation, and a rate over no offers is not a rate
 */
record WorkerPerformance(long offered, long accepted, long declined,
                         Double acceptanceRate, Double declineRate) {
}

/**
 * A job on somebody's screen.
 *
 * @param distanceKm how far the pickup is from where they last reported being —
 *                   the single number that decides whether this is worth taking
 * @param expiresAt  when the card stops being real. The countdown is the client's
 *                   to draw; the deadline is the server's to own
 */
record OfferDto(UUID id, String jobKind, UUID jobRefId, String workerKind,
                String pickupLabel, double pickupLatitude, double pickupLongitude,
                String dropoffLabel, Double dropoffLatitude, Double dropoffLongitude,
                String note, double distanceKm,
                OffsetDateTime expiresAt, OffsetDateTime offeredAt) {
}

/** The job they took. What happens next belongs to the vertical that asked. */
record AssignmentDto(UUID jobId, String jobKind, UUID jobRefId,
                     UUID workerId, String workerKind,
                     String pickupLabel, double pickupLatitude, double pickupLongitude,
                     String dropoffLabel, Double dropoffLatitude, Double dropoffLongitude,
                     String note, OffsetDateTime assignedAt) {
}

/** @param kind DRIVER | COURIER — a dual-mode person signs on to one at a time */
record AvailabilityRequest(@NotBlank @Size(max = 16) String kind, boolean available) {
}

record PositionRequest(@NotNull @DecimalMin("-90") @DecimalMax("90") Double latitude,
                       @NotNull @DecimalMin("-180") @DecimalMax("180") Double longitude) {
}
