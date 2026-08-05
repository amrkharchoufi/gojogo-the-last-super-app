package com.gojogo.economy.internal;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * A catalog product (SPECS §6) — a provisioned seller's, never a person's.
 * The C2C {@code Listing} next door stays exactly as it was; a listing is not
 * a product, and the two never share a table or a checkout.
 *
 * <p>Everything priced, stocked and bought lives on the variants; a product is
 * the page, its variants are the SKUs. Every product has at least one.
 */
@Entity
@Table(name = "product", schema = "economy")
class Product {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "seller_id", nullable = false)
    private UUID sellerId;

    @Column(name = "name", nullable = false)
    private String name;

    @Column(name = "description", nullable = false)
    private String description = "";

    @Column(name = "category", nullable = false)
    private String category;

    @Column(name = "brand")
    private String brand;

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false, length = 16)
    private ProductKind kind = ProductKind.PHYSICAL;

    /** Free-form spec sheet, a JSON object the server never interprets. */
    @Column(name = "specs", nullable = false)
    private String specs = "{}";

    @Column(name = "active", nullable = false)
    private boolean active = true;

    /** Moderation's reversible half of a takedown, same as {@code Listing}. */
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

    @OneToMany(mappedBy = "product", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.LAZY)
    @OrderBy("sortOrder")
    private List<ProductMedia> media = new ArrayList<>();

    @OneToMany(mappedBy = "product", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.LAZY)
    @OrderBy("createdAt")
    private List<ProductVariant> variants = new ArrayList<>();

    protected Product() {
    }

    Product(UUID sellerId, String name, String description, String category,
            String brand, ProductKind kind, String specs) {
        this.sellerId = sellerId;
        this.name = name;
        this.description = description == null ? "" : description;
        this.category = category;
        this.brand = brand;
        this.kind = kind;
        this.specs = specs == null || specs.isBlank() ? "{}" : specs;
    }

    /** Full replacement, same discipline as a listing edit: the form posts the
     *  whole product back. Variants are managed separately — an edit to the
     *  page must not be able to zero anybody's stock. */
    void edit(String name, String description, String category, String brand, String specs) {
        this.name = name;
        this.description = description == null ? "" : description;
        this.category = category;
        this.brand = brand;
        this.specs = specs == null || specs.isBlank() ? "{}" : specs;
        this.updatedAt = OffsetDateTime.now();
    }

    void addMedia(String imageUrl) {
        media.add(new ProductMedia(this, media.size(), imageUrl));
    }

    void replaceMedia(List<String> imageUrls) {
        media.clear();
        imageUrls.forEach(this::addMedia);
    }

    ProductVariant addVariant(String sku, String label, long priceCents, int stock) {
        ProductVariant variant = new ProductVariant(this, sku, label, priceCents, stock);
        variants.add(variant);
        return variant;
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

    boolean isHidden() {
        return hiddenAt != null;
    }

    void setHidden(boolean hidden) {
        this.hiddenAt = hidden ? OffsetDateTime.now() : null;
    }

    /** Visible in the public catalog — the seller's switch, moderation's, and
     *  nothing else. The seller's suspension is checked at the seller. */
    boolean isBrowsable() {
        return active && hiddenAt == null;
    }

    UUID getId() {
        return id;
    }

    UUID getSellerId() {
        return sellerId;
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

    String getBrand() {
        return brand;
    }

    ProductKind getKind() {
        return kind;
    }

    String getSpecs() {
        return specs;
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

    List<ProductMedia> getMedia() {
        return media;
    }

    List<ProductVariant> getVariants() {
        return variants;
    }
}
