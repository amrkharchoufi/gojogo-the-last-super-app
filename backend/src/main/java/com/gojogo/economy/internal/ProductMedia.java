package com.gojogo.economy.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

import java.util.UUID;

/** One image in a product's gallery, same shape as {@code ListingMedia}. */
@Entity
@Table(name = "product_media", schema = "economy")
class ProductMedia {

    @Id
    @GeneratedValue
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "product_id")
    private Product product;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    @Column(name = "image_url", nullable = false)
    private String imageUrl;

    protected ProductMedia() {
    }

    ProductMedia(Product product, int sortOrder, String imageUrl) {
        this.product = product;
        this.sortOrder = sortOrder;
        this.imageUrl = imageUrl;
    }

    String getImageUrl() {
        return imageUrl;
    }
}
