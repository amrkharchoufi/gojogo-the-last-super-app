package com.gojogo.dispatch.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * One job put in front of one worker. Kept after it closes — a declined offer is
 * how an acceptance rate is computed, and both halves are the audit trail behind
 * "why was I never sent that trip".
 */
@Entity
@Table(name = "offer", schema = "dispatch")
class Offer {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "job_id", nullable = false)
    private UUID jobId;

    @Column(name = "worker_id", nullable = false)
    private UUID workerId;

    @Column(nullable = false)
    private int wave;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private OfferState state = OfferState.OFFERED;

    @Column(name = "offered_at", nullable = false)
    private OffsetDateTime offeredAt;

    @Column(name = "expires_at", nullable = false)
    private OffsetDateTime expiresAt;

    @Column(name = "responded_at")
    private OffsetDateTime respondedAt;

    protected Offer() {
    }

    Offer(UUID jobId, UUID workerId, int wave, OffsetDateTime expiresAt) {
        this.jobId = jobId;
        this.workerId = workerId;
        this.wave = wave;
        this.expiresAt = expiresAt;
        this.offeredAt = OffsetDateTime.now();
    }

    void close(OfferState outcome) {
        this.state = outcome;
        this.respondedAt = OffsetDateTime.now();
    }

    boolean isLapsed(OffsetDateTime now) {
        return state.isOpen() && expiresAt.isBefore(now);
    }

    UUID getId() {
        return id;
    }

    UUID getJobId() {
        return jobId;
    }

    UUID getWorkerId() {
        return workerId;
    }

    int getWave() {
        return wave;
    }

    OfferState getState() {
        return state;
    }

    OffsetDateTime getOfferedAt() {
        return offeredAt;
    }

    OffsetDateTime getExpiresAt() {
        return expiresAt;
    }

    OffsetDateTime getRespondedAt() {
        return respondedAt;
    }
}
