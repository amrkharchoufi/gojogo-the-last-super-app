package com.gojogo.travel.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

import java.time.OffsetDateTime;
import java.util.UUID;

/** One trip, from "I'd like to go there" to a receipt. See V31. */
@Entity
@Table(name = "ride", schema = "travel")
class Ride {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "rider_id", nullable = false, updatable = false)
    private UUID riderId;

    @Column(nullable = false, length = 16)
    private String category;

    @Column(name = "pickup_latitude", nullable = false)
    private double pickupLatitude;

    @Column(name = "pickup_longitude", nullable = false)
    private double pickupLongitude;

    @Column(name = "pickup_label", nullable = false, length = 200)
    private String pickupLabel = "";

    @Column(name = "dropoff_latitude", nullable = false)
    private double dropoffLatitude;

    @Column(name = "dropoff_longitude", nullable = false)
    private double dropoffLongitude;

    @Column(name = "dropoff_label", nullable = false, length = 200)
    private String dropoffLabel = "";

    @Column(nullable = false, length = 280)
    private String note = "";

    @Column(name = "distance_metres", nullable = false)
    private int distanceMetres;

    @Column(name = "duration_seconds", nullable = false)
    private int durationSeconds;

    @Column(name = "suggested_fare_minor", nullable = false)
    private long suggestedFareMinor;

    @Column(name = "offered_fare_minor", nullable = false)
    private long offeredFareMinor;

    @Column(name = "agreed_fare_minor")
    private Long agreedFareMinor;

    @Column(nullable = false, length = 3)
    private String currency = "USD";

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 24)
    private RideState state = RideState.REQUESTED;

    @Column(name = "driver_worker_id")
    private UUID driverWorkerId;

    @Column(name = "driver_user_id")
    private UUID driverUserId;

    @Column(name = "vehicle_label", nullable = false, length = 120)
    private String vehicleLabel = "";

    @Column(name = "vehicle_plate", nullable = false, length = 20)
    private String vehiclePlate = "";

    @Column(name = "conversation_id")
    private UUID conversationId;

    @Column(name = "expires_at", nullable = false)
    private OffsetDateTime expiresAt;

    @Column(name = "requested_at", nullable = false)
    private OffsetDateTime requestedAt;

    @Column(name = "confirmed_at")
    private OffsetDateTime confirmedAt;

    @Column(name = "arrived_at")
    private OffsetDateTime arrivedAt;

    @Column(name = "started_at")
    private OffsetDateTime startedAt;

    @Column(name = "completed_at")
    private OffsetDateTime completedAt;

    @Column(name = "cancelled_at")
    private OffsetDateTime cancelledAt;

    @Column(name = "cancel_reason", length = 280)
    private String cancelReason;

    @Column(name = "cancel_fee_minor", nullable = false)
    private long cancelFeeMinor;

    /** Tokens the driver paid to take this trip, frozen at CONFIRMED alongside
     *  the fare — it is what a cancellation gives back, and re-deriving it from
     *  a price list that has since moved would return the wrong number. */
    @Column(name = "token_cost", nullable = false)
    private int tokenCost;

    @Column(name = "rider_rating")
    private Integer riderRating;

    @Column(name = "driver_rating")
    private Integer driverRating;

    @Column(name = "state_changed_at", nullable = false)
    private OffsetDateTime stateChangedAt;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    @Version
    @Column(nullable = false)
    private int version;

    protected Ride() {
    }

    Ride(UUID riderId, String category, double pickupLatitude, double pickupLongitude,
         String pickupLabel, double dropoffLatitude, double dropoffLongitude,
         String dropoffLabel, String note, long distanceMetres, long durationSeconds,
         long suggestedFareMinor, long offeredFareMinor, String currency,
         OffsetDateTime expiresAt) {
        this.riderId = riderId;
        this.category = category;
        this.pickupLatitude = pickupLatitude;
        this.pickupLongitude = pickupLongitude;
        this.pickupLabel = trim(pickupLabel, 200);
        this.dropoffLatitude = dropoffLatitude;
        this.dropoffLongitude = dropoffLongitude;
        this.dropoffLabel = trim(dropoffLabel, 200);
        this.note = trim(note, 280);
        this.distanceMetres = (int) Math.min(Integer.MAX_VALUE, distanceMetres);
        this.durationSeconds = (int) Math.min(Integer.MAX_VALUE, durationSeconds);
        this.suggestedFareMinor = suggestedFareMinor;
        this.offeredFareMinor = offeredFareMinor;
        this.currency = currency;
        this.expiresAt = expiresAt;
        this.requestedAt = OffsetDateTime.now();
        this.stateChangedAt = this.requestedAt;
        this.createdAt = this.requestedAt;
    }

    // MARK: Negotiation

    /** A driver countered, so the rider now has a choice to make. */
    void enterNegotiation() {
        if (state == RideState.REQUESTED) moveTo(RideState.NEGOTIATING);
    }

    /**
     * Matched. The fare freezes here and is never recomputed — a price that moves
     * after a handshake is not a handshake.
     */
    void confirm(UUID workerId, UUID driverUserId, String vehicleLabel, String vehiclePlate,
                 long agreedFareMinor) {
        this.driverWorkerId = workerId;
        this.driverUserId = driverUserId;
        this.vehicleLabel = trim(vehicleLabel, 120);
        this.vehiclePlate = trim(vehiclePlate, 20);
        this.agreedFareMinor = agreedFareMinor;
        this.confirmedAt = OffsetDateTime.now();
        moveTo(RideState.CONFIRMED);
    }

    /** What the driver was charged to take it. Recorded after the movement, so
     *  the row never claims a spend the ledger does not have. */
    void recordTokenCost(int tokens) {
        this.tokenCost = Math.max(0, tokens);
    }

    void attachConversation(UUID conversationId) {
        this.conversationId = conversationId;
    }

    // MARK: The trip

    void markArriving() {
        this.arrivedAt = OffsetDateTime.now();
        moveTo(RideState.ARRIVING);
    }

    void start() {
        this.startedAt = OffsetDateTime.now();
        moveTo(RideState.IN_TRIP);
    }

    void complete() {
        this.completedAt = OffsetDateTime.now();
        moveTo(RideState.COMPLETED);
    }

    void cancel(boolean byRider, String reason, long feeMinor) {
        this.cancelledAt = OffsetDateTime.now();
        this.cancelReason = reason == null || reason.isBlank() ? null : trim(reason, 280);
        this.cancelFeeMinor = feeMinor;
        moveTo(byRider ? RideState.CANCELLED_RIDER : RideState.CANCELLED_DRIVER);
    }

    void expire() {
        moveTo(RideState.EXPIRED);
    }

    // MARK: Ratings

    /** The rider's verdict on the driver. */
    void rateDriver(int stars) {
        this.driverRating = Math.clamp(stars, 1, 5);
    }

    /** And the reverse. */
    void rateRider(int stars) {
        this.riderRating = Math.clamp(stars, 1, 5);
    }

    /**
     * Whether {@code viewer} may see the rating the other side left.
     *
     * <p>Only once both are in. A driver who can read a one-star before writing
     * their own is being invited to answer it, which is how a mutual rating stops
     * measuring the trip and starts measuring the last person to tap.
     */
    boolean ratingsVisibleTo(UUID viewer) {
        return riderRating != null && driverRating != null;
    }

    private void moveTo(RideState next) {
        this.state = next;
        this.stateChangedAt = OffsetDateTime.now();
    }

    private static String trim(String value, int max) {
        if (value == null) return "";
        String trimmed = value.trim();
        return trimmed.length() <= max ? trimmed : trimmed.substring(0, max);
    }

    UUID getId() { return id; }
    UUID getRiderId() { return riderId; }
    String getCategory() { return category; }
    double getPickupLatitude() { return pickupLatitude; }
    double getPickupLongitude() { return pickupLongitude; }
    String getPickupLabel() { return pickupLabel; }
    double getDropoffLatitude() { return dropoffLatitude; }
    double getDropoffLongitude() { return dropoffLongitude; }
    String getDropoffLabel() { return dropoffLabel; }
    String getNote() { return note; }
    int getDistanceMetres() { return distanceMetres; }
    int getDurationSeconds() { return durationSeconds; }
    long getSuggestedFareMinor() { return suggestedFareMinor; }
    long getOfferedFareMinor() { return offeredFareMinor; }
    Long getAgreedFareMinor() { return agreedFareMinor; }
    String getCurrency() { return currency; }
    RideState getState() { return state; }
    UUID getDriverWorkerId() { return driverWorkerId; }
    UUID getDriverUserId() { return driverUserId; }
    String getVehicleLabel() { return vehicleLabel; }
    String getVehiclePlate() { return vehiclePlate; }
    UUID getConversationId() { return conversationId; }
    OffsetDateTime getExpiresAt() { return expiresAt; }
    OffsetDateTime getRequestedAt() { return requestedAt; }
    OffsetDateTime getConfirmedAt() { return confirmedAt; }
    OffsetDateTime getStartedAt() { return startedAt; }
    OffsetDateTime getCompletedAt() { return completedAt; }
    String getCancelReason() { return cancelReason; }
    long getCancelFeeMinor() { return cancelFeeMinor; }
    int getTokenCost() { return tokenCost; }
    Integer getRiderRating() { return riderRating; }
    Integer getDriverRating() { return driverRating; }
}
