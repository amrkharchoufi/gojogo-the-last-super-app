package com.gojogo.delivery.internal;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * A restaurant in the delivery catalog. Seeded by Flyway today — merchant
 * self-onboarding belongs to the {@code partner} vertical in a later phase.
 */
@Entity
@Table(name = "merchant", schema = "delivery")
class Merchant {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "name", nullable = false)
    private String name;

    @Column(name = "cuisine", nullable = false)
    private String cuisine;

    @Column(name = "rating", nullable = false)
    private BigDecimal rating;

    @Column(name = "review_count", nullable = false)
    private int reviewCount;

    @Column(name = "eta_minutes", nullable = false)
    private int etaMinutes;

    @Column(name = "delivery_fee_cents", nullable = false)
    private int deliveryFeeCents;

    @Column(name = "image_url")
    private String imageUrl;

    @Column(name = "promo")
    private String promo;

    @Column(name = "latitude", nullable = false)
    private double latitude;

    @Column(name = "longitude", nullable = false)
    private double longitude;

    @Column(name = "active", nullable = false)
    private boolean active = true;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @ElementCollection(fetch = FetchType.LAZY)
    @CollectionTable(name = "merchant_category", schema = "delivery",
        joinColumns = @JoinColumn(name = "merchant_id"))
    @Column(name = "category")
    private Set<String> categories = new LinkedHashSet<>();

    @ElementCollection(fetch = FetchType.LAZY)
    @CollectionTable(name = "merchant_tag", schema = "delivery",
        joinColumns = @JoinColumn(name = "merchant_id"))
    @Column(name = "tag")
    private Set<String> tags = new LinkedHashSet<>();

    @OneToMany(fetch = FetchType.LAZY)
    @JoinColumn(name = "merchant_id")
    @OrderBy("sortOrder")
    private List<MenuSection> menu = new ArrayList<>();

    protected Merchant() {
    }

    UUID getId() {
        return id;
    }

    String getName() {
        return name;
    }

    String getCuisine() {
        return cuisine;
    }

    BigDecimal getRating() {
        return rating;
    }

    int getReviewCount() {
        return reviewCount;
    }

    int getEtaMinutes() {
        return etaMinutes;
    }

    int getDeliveryFeeCents() {
        return deliveryFeeCents;
    }

    String getImageUrl() {
        return imageUrl;
    }

    String getPromo() {
        return promo;
    }

    double getLatitude() {
        return latitude;
    }

    double getLongitude() {
        return longitude;
    }

    Set<String> getCategories() {
        return categories;
    }

    Set<String> getTags() {
        return tags;
    }

    List<MenuSection> getMenu() {
        return menu;
    }
}
