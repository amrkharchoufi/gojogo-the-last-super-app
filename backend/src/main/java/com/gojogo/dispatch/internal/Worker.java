package com.gojogo.dispatch.internal;

import com.gojogo.dispatch.VehicleCategory;
import com.gojogo.dispatch.WorkerKind;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.OffsetDateTime;
import java.util.UUID;

/** One person's registration in one registry. See V29 for why the columns are shaped this way. */
@Entity
@Table(name = "worker", schema = "dispatch")
class Worker {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private WorkerKind kind;

    @Column(name = "partner_account_id")
    private UUID partnerAccountId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private VehicleCategory category;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private WorkerStatus status = WorkerStatus.OFFLINE;

    @Column(nullable = false)
    private boolean suspended = false;

    @Column(name = "home_region", nullable = false, length = 60)
    private String homeRegion = "";

    @Column
    private Double latitude;

    @Column
    private Double longitude;

    @Column(name = "position_at")
    private OffsetDateTime positionAt;

    @Column(nullable = false, precision = 3, scale = 2)
    private BigDecimal rating = new BigDecimal("5.00");

    @Column(name = "rating_count", nullable = false)
    private int ratingCount;

    @Column(name = "idle_since", nullable = false)
    private OffsetDateTime idleSince;

    @Column(name = "offered_count", nullable = false)
    private int offeredCount;

    @Column(name = "accepted_count", nullable = false)
    private int acceptedCount;

    @Column(name = "declined_count", nullable = false)
    private int declinedCount;

    @Column(name = "expired_count", nullable = false)
    private int expiredCount;

    @Column(name = "completed_count", nullable = false)
    private int completedCount;

    @Column(name = "cancelled_count", nullable = false)
    private int cancelledCount;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected Worker() {
    }

    Worker(UUID userId, WorkerKind kind, UUID partnerAccountId, VehicleCategory category,
           String homeRegion) {
        this.userId = userId;
        this.kind = kind;
        this.partnerAccountId = partnerAccountId;
        this.category = category;
        this.homeRegion = homeRegion == null ? "" : homeRegion;
        this.idleSince = OffsetDateTime.now();
        this.createdAt = this.idleSince;
    }

    // MARK: Availability

    /**
     * Signing on or off. Refuses to go available while mid-job — a worker who
     * wants out of a job cancels it; toggling a switch is not how you abandon
     * somebody standing on a pavement.
     */
    void setAvailable(boolean available) {
        if (status == WorkerStatus.BUSY) return;
        WorkerStatus next = available ? WorkerStatus.AVAILABLE : WorkerStatus.OFFLINE;
        if (status != next) {
            status = next;
            if (next == WorkerStatus.AVAILABLE) idleSince = OffsetDateTime.now();
        }
    }

    void markBusy() {
        status = WorkerStatus.BUSY;
    }

    /**
     * Back on the market after a job ends. Deliberately returns them to
     * AVAILABLE rather than to whatever they were before: somebody who just
     * finished a delivery is holding their phone, and the alternative — going
     * silently offline the moment you finish — is how a courier misses the rest
     * of their evening.
     */
    void release() {
        status = suspended ? WorkerStatus.OFFLINE : WorkerStatus.AVAILABLE;
        idleSince = OffsetDateTime.now();
    }

    void setSuspended(boolean value) {
        this.suspended = value;
        if (value && status == WorkerStatus.AVAILABLE) status = WorkerStatus.OFFLINE;
    }

    void reportPosition(double lat, double lon) {
        this.latitude = lat;
        this.longitude = lon;
        this.positionAt = OffsetDateTime.now();
    }

    void setCategory(VehicleCategory value) {
        this.category = value;
    }

    // MARK: Counters

    void countOffered() {
        offeredCount++;
    }

    void countAccepted() {
        acceptedCount++;
    }

    void countDeclined() {
        declinedCount++;
    }

    void countExpired() {
        expiredCount++;
    }

    void countCancelled() {
        cancelledCount++;
    }

    /**
     * A finished job, and the rating that came with it if there was one.
     *
     * <p>A running mean rather than a stored list: the ratings themselves belong
     * to the vertical that collected them (a trip's rating is part of the trip),
     * and dispatch needs only the number it filters and ranks on.
     */
    void countCompleted(Integer stars) {
        completedCount++;
        if (stars == null) return;
        int clamped = Math.clamp(stars, 1, 5);
        BigDecimal total = rating.multiply(BigDecimal.valueOf(ratingCount))
            .add(BigDecimal.valueOf(clamped));
        ratingCount++;
        rating = total.divide(BigDecimal.valueOf(ratingCount), 2, RoundingMode.HALF_UP);
    }

    // MARK: Reads

    UUID getId() {
        return id;
    }

    UUID getUserId() {
        return userId;
    }

    WorkerKind getKind() {
        return kind;
    }

    UUID getPartnerAccountId() {
        return partnerAccountId;
    }

    VehicleCategory getCategory() {
        return category;
    }

    WorkerStatus getStatus() {
        return status;
    }

    boolean isSuspended() {
        return suspended;
    }

    String getHomeRegion() {
        return homeRegion;
    }

    Double getLatitude() {
        return latitude;
    }

    Double getLongitude() {
        return longitude;
    }

    OffsetDateTime getPositionAt() {
        return positionAt;
    }

    BigDecimal getRating() {
        return rating;
    }

    int getRatingCount() {
        return ratingCount;
    }

    OffsetDateTime getIdleSince() {
        return idleSince;
    }

    int getOfferedCount() {
        return offeredCount;
    }

    int getAcceptedCount() {
        return acceptedCount;
    }

    int getDeclinedCount() {
        return declinedCount;
    }

    int getExpiredCount() {
        return expiredCount;
    }

    int getCompletedCount() {
        return completedCount;
    }

    int getCancelledCount() {
        return cancelledCount;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }
}
