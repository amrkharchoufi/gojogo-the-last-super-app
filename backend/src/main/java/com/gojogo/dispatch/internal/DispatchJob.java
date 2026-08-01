package com.gojogo.dispatch.internal;

import com.gojogo.dispatch.JobKind;
import com.gojogo.dispatch.VehicleCategory;
import com.gojogo.dispatch.WorkerKind;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

import java.time.OffsetDateTime;
import java.util.Arrays;
import java.util.EnumSet;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * One search. Named {@code DispatchJob} rather than {@code Job} because a simple
 * class name is a Hibernate entity name and a Spring bean name across the whole
 * application, and "Job" is a word three more modules will want (see the
 * incidents log).
 */
@Entity
@Table(name = "job", schema = "dispatch")
class DispatchJob {

    @Id
    @GeneratedValue
    private UUID id;

    @Enumerated(EnumType.STRING)
    @Column(name = "job_kind", nullable = false, length = 16)
    private JobKind jobKind;

    @Column(name = "job_ref_id", nullable = false)
    private UUID jobRefId;

    @Column(name = "requested_by")
    private UUID requestedBy;

    @Enumerated(EnumType.STRING)
    @Column(name = "worker_kind", nullable = false, length = 16)
    private WorkerKind workerKind;

    /** Comma-separated {@link VehicleCategory} names; see {@link #categories()}. */
    @Column(nullable = false, length = 120)
    private String categories;

    @Column(name = "pickup_latitude", nullable = false)
    private double pickupLatitude;

    @Column(name = "pickup_longitude", nullable = false)
    private double pickupLongitude;

    @Column(name = "pickup_label", nullable = false, length = 160)
    private String pickupLabel = "";

    @Column(name = "dropoff_latitude")
    private Double dropoffLatitude;

    @Column(name = "dropoff_longitude")
    private Double dropoffLongitude;

    @Column(name = "dropoff_label", nullable = false, length = 160)
    private String dropoffLabel = "";

    @Column(nullable = false, length = 200)
    private String note = "";

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private JobState state = JobState.SEARCHING;

    @Column(nullable = false)
    private int wave;

    @Column(name = "next_wave_at", nullable = false)
    private OffsetDateTime nextWaveAt;

    @Column(name = "expires_at", nullable = false)
    private OffsetDateTime expiresAt;

    @Column(name = "assigned_worker_id")
    private UUID assignedWorkerId;

    @Column(name = "assigned_at")
    private OffsetDateTime assignedAt;

    @Column(name = "closed_at")
    private OffsetDateTime closedAt;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    /**
     * First acceptance wins. Two couriers each believing the order is theirs is
     * the one outcome this table exists to prevent, and with more than one task
     * running the poller the check has to be in the database rather than in a
     * service.
     */
    @Version
    @Column(nullable = false)
    private int version;

    protected DispatchJob() {
    }

    DispatchJob(JobKind jobKind, UUID jobRefId, UUID requestedBy, WorkerKind workerKind,
                Set<VehicleCategory> categories, double pickupLatitude, double pickupLongitude,
                String pickupLabel, Double dropoffLatitude, Double dropoffLongitude,
                String dropoffLabel, String note,
                OffsetDateTime startAt, OffsetDateTime expiresAt) {
        this.jobKind = jobKind;
        this.jobRefId = jobRefId;
        this.requestedBy = requestedBy;
        this.workerKind = workerKind;
        this.categories = encode(categories);
        this.pickupLatitude = pickupLatitude;
        this.pickupLongitude = pickupLongitude;
        this.pickupLabel = trim(pickupLabel, 160);
        this.dropoffLatitude = dropoffLatitude;
        this.dropoffLongitude = dropoffLongitude;
        this.dropoffLabel = trim(dropoffLabel, 160);
        this.note = trim(note, 200);
        this.nextWaveAt = startAt;
        this.expiresAt = expiresAt;
        this.createdAt = OffsetDateTime.now();
    }

    static String encode(Set<VehicleCategory> categories) {
        return categories == null || categories.isEmpty()
            ? ""
            : categories.stream().map(Enum::name).sorted().collect(Collectors.joining(","));
    }

    /**
     * The categories that would do, decoded.
     *
     * <p>An empty column means "anything", not "nothing" — a request that named
     * no category is a caller who does not care, and refusing every worker would
     * be a search that could never succeed. A name this build no longer knows is
     * skipped rather than thrown on: a stored row outlives the enum that wrote
     * it, and a rollback must not make old jobs unreadable.
     */
    Set<VehicleCategory> categories() {
        if (categories == null || categories.isBlank()) return EnumSet.allOf(VehicleCategory.class);
        Set<VehicleCategory> parsed = EnumSet.noneOf(VehicleCategory.class);
        for (String name : Arrays.stream(categories.split(",")).map(String::trim).toList()) {
            for (VehicleCategory candidate : VehicleCategory.values()) {
                if (candidate.name().equals(name)) parsed.add(candidate);
            }
        }
        return parsed.isEmpty() ? EnumSet.allOf(VehicleCategory.class) : parsed;
    }

    /** Opens the next ring. Returns the wave number that is now current. */
    int openWave(OffsetDateTime nextAt) {
        wave++;
        nextWaveAt = nextAt;
        return wave;
    }

    /** Pushes the next wave back without counting one — used when a ring found
     *  nobody new to ask, so the search widens on schedule instead of spinning. */
    void deferWave(OffsetDateTime nextAt) {
        nextWaveAt = nextAt;
    }

    void assignTo(UUID workerId) {
        this.state = JobState.ASSIGNED;
        this.assignedWorkerId = workerId;
        this.assignedAt = OffsetDateTime.now();
    }

    void close(JobState terminal) {
        this.state = terminal;
        this.closedAt = OffsetDateTime.now();
    }

    /** Cancelling an assigned job clears the worker: the row records that the
     *  search ended, and who was on it lives in the offer that was accepted. */
    void unassign() {
        this.assignedWorkerId = null;
        this.assignedAt = null;
    }

    private static String trim(String value, int max) {
        if (value == null) return "";
        String trimmed = value.trim();
        return trimmed.length() <= max ? trimmed : trimmed.substring(0, max);
    }

    UUID getId() {
        return id;
    }

    JobKind getJobKind() {
        return jobKind;
    }

    UUID getJobRefId() {
        return jobRefId;
    }

    UUID getRequestedBy() {
        return requestedBy;
    }

    WorkerKind getWorkerKind() {
        return workerKind;
    }

    double getPickupLatitude() {
        return pickupLatitude;
    }

    double getPickupLongitude() {
        return pickupLongitude;
    }

    String getPickupLabel() {
        return pickupLabel;
    }

    Double getDropoffLatitude() {
        return dropoffLatitude;
    }

    Double getDropoffLongitude() {
        return dropoffLongitude;
    }

    String getDropoffLabel() {
        return dropoffLabel;
    }

    String getNote() {
        return note;
    }

    JobState getState() {
        return state;
    }

    int getWave() {
        return wave;
    }

    OffsetDateTime getNextWaveAt() {
        return nextWaveAt;
    }

    OffsetDateTime getExpiresAt() {
        return expiresAt;
    }

    UUID getAssignedWorkerId() {
        return assignedWorkerId;
    }

    OffsetDateTime getAssignedAt() {
        return assignedAt;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }
}
