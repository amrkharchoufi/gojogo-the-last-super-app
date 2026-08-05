package com.gojogo.economy.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/** One use of a promotion by one buyer — what {@code per_user_limit} counts. */
@Entity
@Table(name = "product_promotion_redemption", schema = "economy")
class ProductPromotionRedemption {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "promotion_id", nullable = false)
    private UUID promotionId;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "order_id", nullable = false)
    private UUID orderId;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    protected ProductPromotionRedemption() {
    }

    ProductPromotionRedemption(UUID promotionId, UUID userId, UUID orderId) {
        this.promotionId = promotionId;
        this.userId = userId;
        this.orderId = orderId;
    }
}
