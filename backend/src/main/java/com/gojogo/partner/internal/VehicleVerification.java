package com.gojogo.partner.internal;

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
 * A passenger being asked whether the car was the car — and their answer, if
 * they give one. See V33.
 *
 * <p><strong>The invitation and the answer are one row</strong>, because the
 * unanswered state is the interesting one: it is what the expiry sweep looks
 * for, and what "we already asked somebody" means when the next trip finishes.
 * Two tables would have made "is there an invitation out on this vehicle" a
 * join, and it is the question this whole mechanism is paced by.
 *
 * <p><strong>Five answers, not a score.</strong> They are the questions SPECS §4
 * names, and a moderator looking at a flagged vehicle reads them individually:
 * "the driver was not the person in the app" is a different problem from "the
 * tyres were bald", and a single number would have thrown that away.
 */
@Entity
@Table(name = "vehicle_verification", schema = "partner")
class VehicleVerification {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "vehicle_id", nullable = false, updatable = false)
    private UUID vehicleId;

    @Column(name = "account_id", nullable = false, updatable = false)
    private UUID accountId;

    @Column(name = "passenger_id", nullable = false, updatable = false)
    private UUID passengerId;

    @Column(name = "driver_user_id", nullable = false, updatable = false)
    private UUID driverUserId;

    @Column(name = "ride_id", nullable = false, updatable = false)
    private UUID rideId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private VerificationStatus status = VerificationStatus.PENDING;

    @Column(name = "driver_matched")
    private Boolean driverMatched;

    @Column(name = "photos_matched")
    private Boolean photosMatched;

    @Column(name = "plate_matched")
    private Boolean plateMatched;

    @Column
    private Boolean roadworthy;

    @Column(name = "no_fraud")
    private Boolean noFraud;

    @Column(nullable = false, length = 500)
    private String comment = "";

    @Column(name = "reward_minor", nullable = false)
    private long rewardMinor;

    @Column(name = "expires_at", nullable = false)
    private OffsetDateTime expiresAt;

    @Column(name = "answered_at")
    private OffsetDateTime answeredAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    protected VehicleVerification() {
    }

    VehicleVerification(UUID vehicleId, UUID accountId, UUID passengerId, UUID driverUserId,
                        UUID rideId, OffsetDateTime expiresAt) {
        this.vehicleId = vehicleId;
        this.accountId = accountId;
        this.passengerId = passengerId;
        this.driverUserId = driverUserId;
        this.rideId = rideId;
        this.expiresAt = expiresAt;
        this.createdAt = OffsetDateTime.now();
    }

    boolean isOpen(OffsetDateTime now) {
        return status == VerificationStatus.PENDING && expiresAt.isAfter(now);
    }

    /**
     * Records the passenger's answers.
     *
     * <p><strong>All five must be yes.</strong> Not four out of five and not a
     * weighted score: each question is a different way the car could be wrong,
     * and a badge that survives one "no" is a badge that says nothing. A missing
     * answer counts as a no for the same reason — an unanswered question is not
     * a confirmation.
     */
    void answer(boolean driverMatched, boolean photosMatched, boolean plateMatched,
                boolean roadworthy, boolean noFraud, String comment) {
        this.driverMatched = driverMatched;
        this.photosMatched = photosMatched;
        this.plateMatched = plateMatched;
        this.roadworthy = roadworthy;
        this.noFraud = noFraud;
        this.comment = comment == null ? "" : trim(comment);
        this.answeredAt = OffsetDateTime.now();
        this.status = allYes() ? VerificationStatus.CONFIRMED : VerificationStatus.REJECTED;
    }

    boolean allYes() {
        return Boolean.TRUE.equals(driverMatched) && Boolean.TRUE.equals(photosMatched)
            && Boolean.TRUE.equals(plateMatched) && Boolean.TRUE.equals(roadworthy)
            && Boolean.TRUE.equals(noFraud);
    }

    void recordReward(long amountMinor) {
        this.rewardMinor = Math.max(0, amountMinor);
    }

    /** Nobody answered in time. Not a rejection — a passenger who never opened
     *  the app has said nothing about the car, and treating silence as a
     *  complaint would flag the vehicle of every driver whose passengers are
     *  busy. */
    void expire() {
        if (status == VerificationStatus.PENDING) this.status = VerificationStatus.EXPIRED;
    }

    /** What a moderator reads on a flagged vehicle: the questions answered no. */
    String failureSummary() {
        StringBuilder said = new StringBuilder();
        appendIfNo(said, driverMatched, "the driver wasn't the person in the app");
        appendIfNo(said, photosMatched, "the car didn't match its photos");
        appendIfNo(said, plateMatched, "the plate didn't match");
        appendIfNo(said, roadworthy, "the car wasn't roadworthy");
        appendIfNo(said, noFraud, "something about the trip looked fraudulent");
        return said.isEmpty() ? "a passenger reported a problem" : said.toString();
    }

    private static void appendIfNo(StringBuilder into, Boolean answer, String phrase) {
        if (Boolean.TRUE.equals(answer)) return;
        if (!into.isEmpty()) into.append("; ");
        into.append(phrase);
    }

    private static String trim(String value) {
        String trimmed = value.trim();
        return trimmed.length() <= 500 ? trimmed : trimmed.substring(0, 500);
    }

    UUID getId() { return id; }
    UUID getVehicleId() { return vehicleId; }
    UUID getAccountId() { return accountId; }
    UUID getPassengerId() { return passengerId; }
    UUID getDriverUserId() { return driverUserId; }
    UUID getRideId() { return rideId; }
    VerificationStatus getStatus() { return status; }
    Boolean getDriverMatched() { return driverMatched; }
    Boolean getPhotosMatched() { return photosMatched; }
    Boolean getPlateMatched() { return plateMatched; }
    Boolean getRoadworthy() { return roadworthy; }
    Boolean getNoFraud() { return noFraud; }
    String getComment() { return comment; }
    long getRewardMinor() { return rewardMinor; }
    OffsetDateTime getExpiresAt() { return expiresAt; }
    OffsetDateTime getAnsweredAt() { return answeredAt; }
    OffsetDateTime getCreatedAt() { return createdAt; }
}

/** Where one invitation stands. */
enum VerificationStatus {

    PENDING,
    /** All five answers were yes: the vehicle earns its badge. */
    CONFIRMED,
    /** At least one was no: the vehicle is flagged and its driver suspended. */
    REJECTED,
    /** Nobody answered. Silence, not a complaint. */
    EXPIRED
}
