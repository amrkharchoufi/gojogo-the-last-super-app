package com.gojogo.economy.internal;

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
 * What a buyer owns after a digital purchase — granted at capture (SPECS §6),
 * one row per unit bought. Downloads are minted per request and never stored;
 * the row is the proof of entitlement, not the URL.
 */
@Entity
@Table(name = "entitlement", schema = "economy")
class Entitlement {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "product_id", nullable = false)
    private UUID productId;

    @Column(name = "order_id", nullable = false)
    private UUID orderId;

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false, length = 16)
    private EntitlementKind kind;

    @Column(name = "license_key")
    private String licenseKey;

    /** Null = does not expire. Reserved for the day subscriptions exist. */
    @Column(name = "expires_at")
    private OffsetDateTime expiresAt;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    protected Entitlement() {
    }

    Entitlement(UUID userId, UUID productId, UUID orderId, EntitlementKind kind,
                String licenseKey) {
        this.userId = userId;
        this.productId = productId;
        this.orderId = orderId;
        this.kind = kind;
        this.licenseKey = licenseKey;
    }

    boolean isLive(OffsetDateTime at) {
        return expiresAt == null || at.isBefore(expiresAt);
    }

    UUID getId() {
        return id;
    }

    UUID getUserId() {
        return userId;
    }

    UUID getProductId() {
        return productId;
    }

    UUID getOrderId() {
        return orderId;
    }

    EntitlementKind getKind() {
        return kind;
    }

    String getLicenseKey() {
        return licenseKey;
    }

    OffsetDateTime getExpiresAt() {
        return expiresAt;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }
}
