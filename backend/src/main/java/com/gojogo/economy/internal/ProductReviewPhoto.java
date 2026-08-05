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

/** One photo on a review — the same shape as every other media child table. */
@Entity
@Table(name = "review_photo", schema = "economy")
class ProductReviewPhoto {

    @Id
    @GeneratedValue
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "review_id")
    private ProductReview review;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    @Column(name = "image_url", nullable = false)
    private String imageUrl;

    protected ProductReviewPhoto() {
    }

    ProductReviewPhoto(ProductReview review, int sortOrder, String imageUrl) {
        this.review = review;
        this.sortOrder = sortOrder;
        this.imageUrl = imageUrl;
    }

    String getImageUrl() {
        return imageUrl;
    }
}
