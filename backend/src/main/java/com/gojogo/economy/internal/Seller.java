package com.gojogo.economy.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * A provisioned merchant seller — what a partner {@code SELLER} approval
 * creates. The catalog hangs off this row; the row itself is deliberately thin,
 * because everything about who this business is lives in {@code partner} and
 * {@code profile}, and everything about what it sells lives on the products.
 *
 * <p>Shipping and tax are the flat per-merchant config SPECS §6 settles for.
 * No tax engine; revisit per market.
 */
@Entity
@Table(name = "seller", schema = "economy")
class Seller {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "display_name", nullable = false)
    private String displayName;

    @Column(name = "logo_url")
    private String logoUrl;

    @Column(name = "shipping_flat_cents", nullable = false)
    private int shippingFlatCents;

    /** 0 = shipping is never free. */
    @Column(name = "free_shipping_over_cents", nullable = false)
    private int freeShippingOverCents;

    @Column(name = "tax_bps", nullable = false)
    private int taxBps;

    /** The platform's block, set from partner suspension — never the owner's. */
    @Column(name = "suspended", nullable = false)
    private boolean suspended;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    protected Seller() {
    }

    Seller(UUID ownerUserId, String displayName, String logoUrl) {
        this.ownerUserId = ownerUserId;
        this.displayName = displayName;
        this.logoUrl = logoUrl;
    }

    /** What a basket of {@code subtotalCents} pays for shipping from this shop. */
    int shippingFor(int subtotalCents) {
        if (freeShippingOverCents > 0 && subtotalCents >= freeShippingOverCents) return 0;
        return shippingFlatCents;
    }

    /** Flat tax on the discounted goods value, rounded down. */
    int taxOn(int baseCents) {
        return Math.floorDiv(baseCents * taxBps, 10_000);
    }

    void configure(String displayName, String logoUrl, int shippingFlatCents,
                   int freeShippingOverCents, int taxBps) {
        this.displayName = displayName;
        this.logoUrl = logoUrl;
        this.shippingFlatCents = Math.max(0, shippingFlatCents);
        this.freeShippingOverCents = Math.max(0, freeShippingOverCents);
        this.taxBps = Math.clamp(taxBps, 0, 10_000);
    }

    void setSuspended(boolean suspended) {
        this.suspended = suspended;
    }

    UUID getId() {
        return id;
    }

    UUID getOwnerUserId() {
        return ownerUserId;
    }

    String getDisplayName() {
        return displayName;
    }

    String getLogoUrl() {
        return logoUrl;
    }

    int getShippingFlatCents() {
        return shippingFlatCents;
    }

    int getFreeShippingOverCents() {
        return freeShippingOverCents;
    }

    int getTaxBps() {
        return taxBps;
    }

    boolean isSuspended() {
        return suspended;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }
}
