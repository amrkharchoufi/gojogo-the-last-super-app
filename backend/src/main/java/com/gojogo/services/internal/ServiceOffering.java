package com.gojogo.services.internal;

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
 * One bookable service (SPECS §7). A null price is {@code PRICE_ON_QUOTE}: the
 * number arrives in the thread and lands on the booking, never back here.
 *
 * <p>Not named {@code Service} — that word is Spring's, and a class by that
 * name would shadow the annotation in every file that touched it.
 */
@Entity
@Table(name = "service", schema = "services")
class ServiceOffering {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "provider_id", nullable = false)
    private UUID providerId;

    @Column(name = "name", nullable = false)
    private String name;

    @Column(name = "description", nullable = false)
    private String description = "";

    @Column(name = "category", nullable = false)
    private String category;

    @Column(name = "duration_minutes", nullable = false)
    private int durationMinutes;

    /** Null = price on quote. */
    @Column(name = "price_cents")
    private Long priceCents;

    @Enumerated(EnumType.STRING)
    @Column(name = "location_kind", nullable = false, length = 16)
    private LocationKind locationKind = LocationKind.AT_PROVIDER;

    @Column(name = "requirements", nullable = false)
    private String requirements = "";

    @Column(name = "active", nullable = false)
    private boolean active = true;

    @Column(name = "hidden_at")
    private OffsetDateTime hiddenAt;

    @Column(name = "rating_sum", nullable = false)
    private long ratingSum;

    @Column(name = "rating_count", nullable = false)
    private int ratingCount;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "updated_at")
    private OffsetDateTime updatedAt;

    protected ServiceOffering() {
    }

    ServiceOffering(UUID providerId, String name, String description, String category,
                    int durationMinutes, Long priceCents, LocationKind locationKind,
                    String requirements) {
        this.providerId = providerId;
        this.name = name;
        this.description = description == null ? "" : description;
        this.category = category;
        this.durationMinutes = durationMinutes;
        this.priceCents = priceCents;
        this.locationKind = locationKind;
        this.requirements = requirements == null ? "" : requirements;
    }

    void edit(String name, String description, String category, int durationMinutes,
              Long priceCents, LocationKind locationKind, String requirements) {
        this.name = name;
        this.description = description == null ? "" : description;
        this.category = category;
        this.durationMinutes = durationMinutes;
        this.priceCents = priceCents;
        this.locationKind = locationKind;
        this.requirements = requirements == null ? "" : requirements;
        this.updatedAt = OffsetDateTime.now();
    }

    void setActive(boolean active) {
        this.active = active;
        this.updatedAt = OffsetDateTime.now();
    }

    void recordReview(int rating) {
        this.ratingSum += rating;
        this.ratingCount += 1;
    }

    void amendReview(int oldRating, int newRating) {
        this.ratingSum += newRating - oldRating;
    }

    boolean isBrowsable() {
        return active && hiddenAt == null;
    }

    boolean isQuoted() {
        return priceCents == null;
    }

    UUID getId() {
        return id;
    }

    UUID getProviderId() {
        return providerId;
    }

    String getName() {
        return name;
    }

    String getDescription() {
        return description;
    }

    String getCategory() {
        return category;
    }

    int getDurationMinutes() {
        return durationMinutes;
    }

    Long getPriceCents() {
        return priceCents;
    }

    LocationKind getLocationKind() {
        return locationKind;
    }

    String getRequirements() {
        return requirements;
    }

    boolean isActive() {
        return active;
    }

    long getRatingSum() {
        return ratingSum;
    }

    int getRatingCount() {
        return ratingCount;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    OffsetDateTime getUpdatedAt() {
        return updatedAt;
    }
}
