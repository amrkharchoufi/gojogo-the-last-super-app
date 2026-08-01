package com.gojogo.travel.internal;

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
 * One price on the table.
 *
 * <p>A row rather than a pair of columns on the ride, because there are two
 * rounds and both sides make them: "they asked 45, I came back with 38, they took
 * it" is a sequence, and a column would collapse it into a number nobody can
 * audit. It is also what lets a rider hold three counters from three drivers at
 * once and choose.
 */
@Entity
@Table(name = "ride_offer", schema = "travel")
class RideOffer {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "ride_id", nullable = false, updatable = false)
    private UUID rideId;

    @Column(name = "driver_worker_id", nullable = false)
    private UUID driverWorkerId;

    @Column(name = "driver_user_id", nullable = false)
    private UUID driverUserId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 8)
    private OfferParty party;

    @Column(name = "amount_minor", nullable = false)
    private long amountMinor;

    @Column(nullable = false)
    private int round;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private RideOfferState state = RideOfferState.PENDING;

    @Column(name = "expires_at", nullable = false)
    private OffsetDateTime expiresAt;

    @Column(name = "responded_at")
    private OffsetDateTime respondedAt;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected RideOffer() {
    }

    RideOffer(UUID rideId, UUID driverWorkerId, UUID driverUserId, OfferParty party,
              long amountMinor, int round, OffsetDateTime expiresAt) {
        this.rideId = rideId;
        this.driverWorkerId = driverWorkerId;
        this.driverUserId = driverUserId;
        this.party = party;
        this.amountMinor = amountMinor;
        this.round = round;
        this.expiresAt = expiresAt;
        this.createdAt = OffsetDateTime.now();
    }

    void close(RideOfferState outcome) {
        this.state = outcome;
        this.respondedAt = OffsetDateTime.now();
    }

    boolean isLapsed(OffsetDateTime now) {
        return state.isOpen() && expiresAt.isBefore(now);
    }

    /** Whether this side may answer it — you never accept your own price. */
    boolean answerableBy(OfferParty other) {
        return state.isOpen() && party != other;
    }

    UUID getId() { return id; }
    UUID getRideId() { return rideId; }
    UUID getDriverWorkerId() { return driverWorkerId; }
    UUID getDriverUserId() { return driverUserId; }
    OfferParty getParty() { return party; }
    long getAmountMinor() { return amountMinor; }
    int getRound() { return round; }
    RideOfferState getState() { return state; }
    OffsetDateTime getExpiresAt() { return expiresAt; }
    OffsetDateTime getCreatedAt() { return createdAt; }
}
