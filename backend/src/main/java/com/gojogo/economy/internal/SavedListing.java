package com.gojogo.economy.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

import java.io.Serializable;
import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "saved_listing", schema = "economy")
@IdClass(SavedListing.Key.class)
class SavedListing {

    @Id
    @Column(name = "listing_id")
    private UUID listingId;

    @Id
    @Column(name = "user_id")
    private UUID userId;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected SavedListing() {
    }

    SavedListing(UUID listingId, UUID userId) {
        this.listingId = listingId;
        this.userId = userId;
        this.createdAt = OffsetDateTime.now();
    }

    record Key(UUID listingId, UUID userId) implements Serializable {
    }
}
