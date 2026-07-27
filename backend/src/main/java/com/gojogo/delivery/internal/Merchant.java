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
 * A restaurant in the delivery catalog. Created for an approved partner through
 * {@code MerchantProvisioningApi} and then managed by its owner; rows with no
 * {@code ownerId} predate onboarding (the deleted V8 seed) or were inserted by
 * hand, and nobody can edit those from the app.
 */
@Entity
@Table(name = "merchant", schema = "delivery")
class Merchant {

    @Id
    @GeneratedValue
    private UUID id;

    /** The profile that manages this restaurant; null for an unowned row. */
    @Column(name = "owner_id")
    private UUID ownerId;

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

    /** The owner's own "we're open" switch. */
    @Column(name = "active", nullable = false)
    private boolean active = true;

    /** A platform block, held apart from {@link #active} so lifting it can't
     *  open a restaurant its owner had closed. */
    @Column(name = "suspended", nullable = false)
    private boolean suspended;

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

    // Read-only side: MenuSection.merchantId is what writes the column, so the
    // menu editor can create a section without going through this collection.
    @OneToMany(fetch = FetchType.LAZY)
    @JoinColumn(name = "merchant_id", insertable = false, updatable = false)
    @OrderBy("sortOrder")
    private List<MenuSection> menu = new ArrayList<>();

    protected Merchant() {
    }

    /**
     * A restaurant provisioned for an approved partner. It starts closed —
     * publishing is the owner's act, once there is a menu to publish — and with
     * catalog defaults for ETA and delivery fee, which the owner then tunes.
     */
    Merchant(UUID ownerId, String name, String cuisine, String imageUrl,
             Double latitude, Double longitude) {
        this.ownerId = ownerId;
        this.name = name;
        this.cuisine = cuisine;
        this.imageUrl = imageUrl;
        this.rating = DEFAULT_RATING;
        this.etaMinutes = DEFAULT_ETA_MINUTES;
        this.deliveryFeeCents = 0;
        this.latitude = latitude == null ? DEFAULT_LATITUDE : latitude;
        this.longitude = longitude == null ? DEFAULT_LONGITUDE : longitude;
        this.active = false;
    }

    /** No reviews yet, and no rating to show. Matches the column default the
     *  seeded rows used, so browse has one shape to render. */
    private static final BigDecimal DEFAULT_RATING = new BigDecimal("4.5");
    private static final int DEFAULT_ETA_MINUTES = 25;
    private static final double DEFAULT_LATITUDE = 33.5731;
    private static final double DEFAULT_LONGITUDE = -7.5898;

    /** Applies the owner's edits. Everything here is theirs to set; rating,
     *  review count and the suspension flag are not. */
    void apply(String name, String cuisine, String imageUrl, String promo,
               int etaMinutes, int deliveryFeeCents,
               Double latitude, Double longitude,
               Set<String> categories, Set<String> tags) {
        this.name = name;
        this.cuisine = cuisine;
        this.imageUrl = imageUrl;
        this.promo = promo == null || promo.isBlank() ? null : promo;
        this.etaMinutes = etaMinutes;
        this.deliveryFeeCents = deliveryFeeCents;
        if (latitude != null && longitude != null) {
            this.latitude = latitude;
            this.longitude = longitude;
        }
        this.categories.clear();
        this.categories.addAll(categories);
        this.tags.clear();
        this.tags.addAll(tags);
    }

    void setActive(boolean active) {
        this.active = active;
    }

    void setSuspended(boolean suspended) {
        this.suspended = suspended;
    }

    UUID getId() {
        return id;
    }

    UUID getOwnerId() {
        return ownerId;
    }

    boolean isActive() {
        return active;
    }

    boolean isSuspended() {
        return suspended;
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
