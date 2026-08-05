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

    /**
     * Seven days of open/close in one column — see {@link OpeningHours} for the
     * format and for why it is a string rather than seven rows (Phase 4 M6).
     *
     * <p>Blank means always open, which is what every restaurant in the catalog
     * before this was: {@link #active} is the only thing that has ever closed
     * one, and it is a switch somebody has to remember to flip twice a day.
     * The two are not alternatives — {@code active} is "we are trading at all",
     * and this is "and right now".
     */
    @Column(name = "opening_hours", nullable = false)
    private String openingHours = "";

    /** Their local time, because hours without a zone are hours in the
     *  server's, and the server's is UTC, which is nobody's lunchtime. */
    @Column(name = "timezone", nullable = false)
    private String timezone = "";

    /**
     * Whether customers may collect in store (Phase 4 M4, SPECS §5).
     *
     * <p>Off until an owner turns it on: collection needs a counter and
     * somebody standing at it, and defaulting it on would advertise a service
     * on behalf of every restaurant already in the catalog. Deliberately
     * <em>not</em> a second "open" switch — {@link #active} closes a restaurant
     * for both, because whether the kitchen is cooking is one fact, and two
     * switches would eventually disagree.
     */
    @Column(name = "pickup_enabled", nullable = false)
    private boolean pickupEnabled;

    /** How long a collection takes to prepare, when it differs from delivery.
     *  Null means "the same": collection is usually quicker with no courier to
     *  wait for, but a kitchen that has not said so is not one to invent a
     *  faster number for. */
    @Column(name = "pickup_prep_minutes")
    private Integer pickupPrepMinutes;

    /** Where to walk to, when that is not simply the restaurant's address —
     *  "side door on Rue Ali", a mall unit. Blank falls back to the name and
     *  the map pin every client already draws. */
    @Column(name = "pickup_address", nullable = false)
    private String pickupAddress = "";

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
               Set<String> categories, Set<String> tags,
               boolean pickupEnabled, Integer pickupPrepMinutes, String pickupAddress,
               String openingHours, String timezone) {
        this.openingHours = openingHours == null ? "" : openingHours.trim();
        this.timezone = timezone == null ? "" : timezone.trim();
        this.pickupEnabled = pickupEnabled;
        this.pickupPrepMinutes = pickupPrepMinutes;
        this.pickupAddress = pickupAddress == null ? "" : pickupAddress.trim();
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

    /**
     * Whether this restaurant would take an order right now — both flags, the
     * same pair the catalog browse checks: {@code active} is the owner saying
     * they are open and {@code suspended} is the platform saying they are not.
     *
     * <p>Read when a scheduled order is promoted (Phase 4 M5), which is the one
     * place in this vertical where the answer can have changed since the
     * customer ordered.
     */
    boolean isOpenForOrders() {
        return active && !suspended;
    }

    /**
     * Trading, and open at that moment (Phase 4 M6).
     *
     * <p>Two questions rather than one because they fail differently: a
     * suspended or unpublished restaurant is not in the catalog at all, and a
     * closed one is there and shut. The caller says which sentence to write.
     */
    boolean isOpenAt(OffsetDateTime instant, java.time.ZoneId platformZone) {
        return isOpenForOrders() && hours(platformZone).openAt(instant);
    }

    /**
     * When they are actually open (Phase 4 M6), in their own local time.
     *
     * <p>Empty is always-open, which is every restaurant that existed before
     * this — a schedule nobody has written must not close a kitchen that has
     * been trading fine. See {@link OpeningHours} for the format and for why it
     * is a string rather than seven rows.
     */
    OpeningHours hours(java.time.ZoneId platformZone) {
        java.time.ZoneId zone = platformZone;
        if (timezone != null && !timezone.isBlank()) {
            try {
                zone = java.time.ZoneId.of(timezone);
            } catch (java.time.DateTimeException notAZone) {
                // Falls back rather than throwing: a typo in a timezone must
                // not take a restaurant's whole page down.
                zone = platformZone;
            }
        }
        return OpeningHours.parse(openingHours, zone);
    }

    String getOpeningHours() {
        return openingHours;
    }

    String getTimezone() {
        return timezone;
    }

    boolean isPickupEnabled() {
        return pickupEnabled;
    }

    Integer getPickupPrepMinutes() {
        return pickupPrepMinutes;
    }

    String getPickupAddress() {
        return pickupAddress;
    }

    /** Where a customer collecting from here actually walks to. */
    String collectionAddress() {
        return pickupAddress.isBlank() ? name : pickupAddress;
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
