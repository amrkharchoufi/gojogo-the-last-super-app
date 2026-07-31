package com.gojogo.delivery.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * That a promotion was actually used, by whom, on what.
 *
 * <p>Exists for the per-user limit, and doubles as the answer to "did this
 * campaign do anything". One row per order — a retried checkout must not count
 * twice against someone's allowance, which the unique index enforces rather than
 * the code remembering to.
 */
@Entity
@Table(name = "promotion_redemption", schema = "delivery")
class PromotionRedemption {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "promotion_id", nullable = false)
    private UUID promotionId;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "order_id", nullable = false)
    private UUID orderId;

    @Column(name = "amount_cents", nullable = false)
    private int amountCents;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    protected PromotionRedemption() {
    }

    PromotionRedemption(UUID promotionId, UUID userId, UUID orderId, int amountCents) {
        this.promotionId = promotionId;
        this.userId = userId;
        this.orderId = orderId;
        this.amountCents = amountCents;
    }
}
