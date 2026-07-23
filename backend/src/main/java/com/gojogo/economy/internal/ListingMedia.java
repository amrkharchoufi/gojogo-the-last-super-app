package com.gojogo.economy.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

import java.util.UUID;

@Entity
@Table(name = "listing_media", schema = "economy")
class ListingMedia {

    @Id
    @GeneratedValue
    private UUID id;

    @ManyToOne(fetch = jakarta.persistence.FetchType.LAZY)
    @JoinColumn(name = "listing_id", nullable = false)
    private Listing listing;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    @Column(name = "image_url", nullable = false)
    private String imageUrl;

    protected ListingMedia() {
    }

    ListingMedia(Listing listing, int sortOrder, String imageUrl) {
        this.listing = listing;
        this.sortOrder = sortOrder;
        this.imageUrl = imageUrl;
    }

    int getSortOrder() {
        return sortOrder;
    }

    String getImageUrl() {
        return imageUrl;
    }
}
