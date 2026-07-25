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

@Entity
@Table(name = "listing", schema = "economy")
class Listing {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "seller_id", nullable = false)
    private UUID sellerId;

    @Column(name = "title", nullable = false)
    private String title;

    @Column(name = "price_cents")
    private Long priceCents;

    @Column(name = "currency", nullable = false)
    private String currency = "USD";

    @Column(name = "category", nullable = false)
    private String category;

    @Column(name = "condition", nullable = false)
    private String condition;

    @Column(name = "location_label", nullable = false)
    private String locationLabel;

    @Column(name = "description", nullable = false)
    private String description = "";

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private ListingStatus status = ListingStatus.ACTIVE;

    @Column(name = "save_count", nullable = false)
    private int saveCount;

    @Column(name = "view_count", nullable = false)
    private int viewCount;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    /** Null until the seller first edits the listing. */
    @Column(name = "updated_at")
    private OffsetDateTime updatedAt;

    @OneToMany(mappedBy = "listing", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.LAZY)
    @OrderBy("sortOrder")
    private List<ListingMedia> media = new ArrayList<>();

    protected Listing() {
    }

    Listing(UUID sellerId, String title, Long priceCents, String currency, String category,
            String condition, String locationLabel, String description) {
        this.sellerId = sellerId;
        this.title = title;
        this.priceCents = priceCents;
        this.currency = currency == null || currency.isBlank() ? "USD" : currency;
        this.category = category;
        this.condition = condition;
        this.locationLabel = locationLabel;
        this.description = description == null ? "" : description;
        this.createdAt = OffsetDateTime.now();
    }

    void addMedia(String imageUrl) {
        media.add(new ListingMedia(this, media.size(), imageUrl));
    }

    /**
     * Applies a seller's edits. Every field is replaced — the edit form always
     * posts the whole listing back, so a "cleared" description means cleared,
     * not "leave it alone".
     */
    void edit(String title, Long priceCents, String currency, String category, String condition,
              String locationLabel, String description) {
        this.title = title;
        this.priceCents = priceCents;
        this.currency = currency;
        this.category = category;
        this.condition = condition;
        this.locationLabel = locationLabel;
        this.description = description == null ? "" : description;
        this.updatedAt = OffsetDateTime.now();
    }

    /** Swaps the photo set wholesale, keeping the given order. */
    void replaceMedia(List<String> imageUrls) {
        media.clear();
        imageUrls.forEach(this::addMedia);
    }

    void setStatus(ListingStatus status) {
        this.status = status;
        this.updatedAt = OffsetDateTime.now();
    }

    UUID getId() {
        return id;
    }

    UUID getSellerId() {
        return sellerId;
    }

    String getTitle() {
        return title;
    }

    Long getPriceCents() {
        return priceCents;
    }

    String getCurrency() {
        return currency;
    }

    String getCategory() {
        return category;
    }

    String getCondition() {
        return condition;
    }

    String getLocationLabel() {
        return locationLabel;
    }

    String getDescription() {
        return description;
    }

    ListingStatus getStatus() {
        return status;
    }

    int getSaveCount() {
        return saveCount;
    }

    int getViewCount() {
        return viewCount;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    OffsetDateTime getUpdatedAt() {
        return updatedAt;
    }

    List<ListingMedia> getMedia() {
        return media;
    }
}
