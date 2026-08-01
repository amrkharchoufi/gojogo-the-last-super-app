package com.gojogo.travel.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * The price list for one vehicle category, effective from a date.
 *
 * <p>A table rather than config-registry keys because the shape is per-category
 * and effective-dated — three columns of structure the flat key/value registry
 * would have to encode into key names. The registry still owns the policy around
 * it: negotiation rounds, TTLs, the cancellation fee.
 */
@Entity
@Table(name = "pricing_config", schema = "travel")
class PricingConfig {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(nullable = false, length = 16)
    private String category;

    @Column(name = "base_minor", nullable = false)
    private long baseMinor;

    @Column(name = "per_km_minor", nullable = false)
    private long perKmMinor;

    @Column(name = "per_minute_minor", nullable = false)
    private long perMinuteMinor;

    @Column(name = "minimum_minor", nullable = false)
    private long minimumMinor;

    @Column(name = "surge_bps", nullable = false)
    private int surgeBps = 10_000;

    @Column(name = "effective_from", nullable = false)
    private OffsetDateTime effectiveFrom;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected PricingConfig() {
    }

    Fares.Pricing toPricing() {
        return new Fares.Pricing(baseMinor, perKmMinor, perMinuteMinor, minimumMinor, surgeBps);
    }

    String getCategory() { return category; }
}
