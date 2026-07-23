package com.gojogo.economy.internal;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
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

    @Column(name = "active", nullable = false)
    private boolean active = true;

    @Column(name = "save_count", nullable = false)
    private int saveCount;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

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

    boolean isActive() {
        return active;
    }

    int getSaveCount() {
        return saveCount;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    List<ListingMedia> getMedia() {
        return media;
    }
}
