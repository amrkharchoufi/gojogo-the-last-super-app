package com.gojogo.partner.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * A car, a bike, a van — and the claim a human reviews about it.
 *
 * <p>It lives in {@code partner} rather than in {@code dispatch} because it is
 * papers and a plate somebody has to match against a photo, which is what this
 * module is for. Dispatch needs one fact out of all of it — which category this
 * worker can be sent — and gets it through the provisioning API at approval.
 * See V30.
 */
@Entity
@Table(name = "vehicle", schema = "partner")
class Vehicle {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "account_id", nullable = false, updatable = false)
    private UUID accountId;

    @Column(name = "user_id", nullable = false, updatable = false)
    private UUID userId;

    /** A {@code com.gojogo.dispatch.VehicleCategory} name; see V30 for why it is
     *  text rather than a shared enum type. */
    @Column(nullable = false, length = 16)
    private String category;

    @Column(nullable = false, length = 60)
    private String make = "";

    @Column(nullable = false, length = 60)
    private String model = "";

    @Column
    private Integer year;

    @Column(nullable = false, length = 30)
    private String color = "";

    @Column(nullable = false, length = 20)
    private String plate = "";

    /**
     * Where the plate was issued, ISO 3166-1 alpha-2.
     *
     * <p>This, not {@link #region}, is what makes a plate unique. A city misses
     * duplicates within one country (a plate issued nationally is the same car
     * whichever city you type) and invents them across borders (Rabat is in both
     * Morocco and Malta).
     */
    @Column(nullable = false, length = 2)
    private String country = "";

    /**
     * The state or province that issued the plate, where one did — empty
     * everywhere plates are national, which is most of the world.
     *
     * <p>Part of the plate's identity only in the countries that subdivide it:
     * Texas ABC-1234 is genuinely not California ABC-1234. The app asks for it
     * exactly there and leaves it blank otherwise, so the uniqueness index reads
     * the same either way.
     */
    @Column(nullable = false, length = 60)
    private String region = "";

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 24)
    private VehicleState state = VehicleState.SUBMITTED;

    @Column(nullable = false)
    private boolean active;

    @Column(name = "registration_expires_on")
    private LocalDate registrationExpiresOn;

    @Column(name = "insurance_expires_on")
    private LocalDate insuranceExpiresOn;

    @Column(name = "review_note", length = 400)
    private String reviewNote;

    @Column(name = "flagged_at")
    private OffsetDateTime flaggedAt;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    protected Vehicle() {
    }

    Vehicle(UUID accountId, UUID userId, String category) {
        this.accountId = accountId;
        this.userId = userId;
        this.category = category;
        this.createdAt = OffsetDateTime.now();
        this.updatedAt = this.createdAt;
    }

    /**
     * Edits the details. Any edit puts an approved vehicle back to
     * {@code SUBMITTED} — a driver who changes the plate on a car a reviewer
     * already looked at has described a different car, and letting that keep the
     * old verdict is the whole shape of the fraud this check exists to catch.
     */
    void apply(String category, String make, String model, Integer year, String color,
               String plate, String country, String region,
               LocalDate registrationExpiresOn, LocalDate insuranceExpiresOn) {
        // Country belongs in here with the plate: "ABC-123, Morocco" and
        // "ABC-123, France" are two cars, so changing it describes a different
        // one and the old verdict cannot follow.
        boolean identityChanged = !this.category.equals(category)
            || !this.plate.equalsIgnoreCase(orEmpty(plate))
            || !this.country.equalsIgnoreCase(orEmpty(country))
            || !this.region.equalsIgnoreCase(orEmpty(region));
        this.category = category;
        this.make = orEmpty(make);
        this.model = orEmpty(model);
        this.year = year;
        this.color = orEmpty(color);
        this.plate = orEmpty(plate);
        this.country = orEmpty(country).toUpperCase();
        this.region = orEmpty(region);
        this.registrationExpiresOn = registrationExpiresOn;
        this.insuranceExpiresOn = insuranceExpiresOn;
        if (identityChanged && state != VehicleState.RETIRED) {
            this.state = VehicleState.SUBMITTED;
            this.reviewNote = null;
            this.flaggedAt = null;
        }
        touch();
    }

    void setActive(boolean value) {
        this.active = value;
        touch();
    }

    /**
     * Back into the queue after a flag — the driver has answered it with a fresh
     * certificate. It does <em>not</em> approve itself: a re-upload is a claim,
     * and the whole point of the flag is that a person looks at it.
     */
    void resubmit() {
        if (state != VehicleState.FLAGGED) return;
        this.state = VehicleState.SUBMITTED;
        this.reviewNote = null;
        this.flaggedAt = null;
        touch();
    }

    void approve(String note) {
        this.state = VehicleState.APPROVED;
        this.reviewNote = note == null || note.isBlank() ? null : note.trim();
        this.flaggedAt = null;
        touch();
    }

    void flag(String note) {
        this.state = VehicleState.FLAGGED;
        this.reviewNote = note == null || note.isBlank() ? null : note.trim();
        this.flaggedAt = OffsetDateTime.now();
        // A flagged vehicle stops being the one dispatch matches on. Leaving it
        // active would mean the fastest way to keep working is to ignore the
        // flag.
        this.active = false;
        touch();
    }

    /** Phase 3 M5's passenger confirmation. The state exists now so the badge
     *  has somewhere to come from and a reviewer's vocabulary doesn't change
     *  under them later. */
    void markCommunityVerified() {
        this.state = VehicleState.COMMUNITY_VERIFIED;
        this.flaggedAt = null;
        touch();
    }

    /** Sold, scrapped, or simply replaced. Kept rather than deleted, because a
     *  trip that happened in this car is a record of this car. */
    void retire() {
        this.state = VehicleState.RETIRED;
        this.active = false;
        touch();
    }

    /**
     * The earliest day this vehicle's papers stop being valid, or null if none
     * are on file. Both must be current — a car with insurance and a lapsed
     * registration is as illegal as the reverse.
     */
    LocalDate papersValidUntil() {
        if (registrationExpiresOn == null) return insuranceExpiresOn;
        if (insuranceExpiresOn == null) return registrationExpiresOn;
        return registrationExpiresOn.isBefore(insuranceExpiresOn)
            ? registrationExpiresOn : insuranceExpiresOn;
    }

    boolean papersExpiredOn(LocalDate day) {
        LocalDate until = papersValidUntil();
        return until != null && until.isBefore(day);
    }

    private void touch() {
        this.updatedAt = OffsetDateTime.now();
    }

    private static String orEmpty(String value) {
        return value == null ? "" : value.trim();
    }

    UUID getId() { return id; }
    UUID getAccountId() { return accountId; }
    UUID getUserId() { return userId; }
    String getCategory() { return category; }
    String getMake() { return make; }
    String getModel() { return model; }
    Integer getYear() { return year; }
    String getColor() { return color; }
    String getPlate() { return plate; }
    String getCountry() { return country; }
    String getRegion() { return region; }
    VehicleState getState() { return state; }
    boolean isActive() { return active; }
    LocalDate getRegistrationExpiresOn() { return registrationExpiresOn; }
    LocalDate getInsuranceExpiresOn() { return insuranceExpiresOn; }
    String getReviewNote() { return reviewNote; }
    OffsetDateTime getFlaggedAt() { return flaggedAt; }
    OffsetDateTime getCreatedAt() { return createdAt; }
}
