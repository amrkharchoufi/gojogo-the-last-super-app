package com.gojogo.economy.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * The SKU level — what is actually priced, stocked and bought. Stock is only
 * ever moved by the conditional bulk updates in {@code ProductRepositories}
 * (oversell-proof, SPECS §6); nothing in Java arithmetic touches it.
 */
@Entity
@Table(name = "product_variant", schema = "economy")
class ProductVariant {

    @Id
    @GeneratedValue
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "product_id")
    private Product product;

    @Column(name = "sku")
    private String sku;

    /** The option values as one display string ("Blue / L"). */
    @Column(name = "label", nullable = false)
    private String label;

    @Column(name = "price_cents", nullable = false)
    private long priceCents;

    @Column(name = "stock", nullable = false)
    private int stock;

    @Column(name = "active", nullable = false)
    private boolean active = true;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    protected ProductVariant() {
    }

    ProductVariant(Product product, String sku, String label, long priceCents, int stock) {
        this.product = product;
        this.sku = sku;
        this.label = label;
        this.priceCents = priceCents;
        this.stock = Math.max(0, stock);
    }

    void edit(String sku, String label, long priceCents, int stock, boolean active) {
        this.sku = sku;
        this.label = label;
        this.priceCents = priceCents;
        this.stock = Math.max(0, stock);
        this.active = active;
    }

    UUID getId() {
        return id;
    }

    Product getProduct() {
        return product;
    }

    String getSku() {
        return sku;
    }

    String getLabel() {
        return label;
    }

    long getPriceCents() {
        return priceCents;
    }

    int getStock() {
        return stock;
    }

    boolean isActive() {
        return active;
    }
}
