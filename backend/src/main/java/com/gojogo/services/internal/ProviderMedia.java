package com.gojogo.services.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

import java.util.UUID;

/** One portfolio photo — public, unlike the qualification papers. */
@Entity
@Table(name = "provider_media", schema = "services")
class ProviderMedia {

    @Id
    @GeneratedValue
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "provider_id")
    private Provider provider;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    @Column(name = "image_url", nullable = false)
    private String imageUrl;

    protected ProviderMedia() {
    }

    ProviderMedia(Provider provider, int sortOrder, String imageUrl) {
        this.provider = provider;
        this.sortOrder = sortOrder;
        this.imageUrl = imageUrl;
    }

    String getImageUrl() {
        return imageUrl;
    }
}
