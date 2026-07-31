package com.gojogo.delivery.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * A merchant's discount (SPECS.md §6's shared promotion shape, delivery first).
 *
 * <p>Applied server-side at pricing time, because a discount the client computed
 * is a discount the client chose. The customer's request carries a code at most;
 * everything about what it is worth is read here.
 */
@Entity
@Table(name = "promotion", schema = "delivery")
class Promotion {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "merchant_id", nullable = false)
    private UUID merchantId;

    /** Null means automatic — it applies to any qualifying basket with nothing
     *  to type. Stored as given, matched case-insensitively. */
    @Column(name = "code")
    private String code;

    @Column(name = "label", nullable = false)
    private String label = "";

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false)
    private Kind kind;

    @Column(name = "value_bps", nullable = false)
    private int valueBps;

    @Column(name = "amount_cents", nullable = false)
    private int amountCents;

    @Column(name = "min_basket_cents", nullable = false)
    private int minBasketCents;

    /** 0 = uncapped. An uncapped percentage is how a merchant accidentally
     *  gives away $80 on one large order. */
    @Column(name = "max_discount_cents", nullable = false)
    private int maxDiscountCents;

    /** 0 = unlimited, counted from {@code promotion_redemption}. */
    @Column(name = "per_user_limit", nullable = false)
    private int perUserLimit;

    @Column(name = "starts_at")
    private OffsetDateTime startsAt;

    @Column(name = "ends_at")
    private OffsetDateTime endsAt;

    @Column(name = "active", nullable = false)
    private boolean active = true;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt = OffsetDateTime.now();

    protected Promotion() {
    }

    Promotion(UUID merchantId, String code, String label, Kind kind, int valueBps,
              int amountCents, int minBasketCents, int maxDiscountCents, int perUserLimit,
              OffsetDateTime startsAt, OffsetDateTime endsAt) {
        this.merchantId = merchantId;
        this.code = code == null || code.isBlank() ? null : code.trim().toUpperCase();
        this.label = label == null ? "" : label;
        this.kind = kind;
        this.valueBps = valueBps;
        this.amountCents = amountCents;
        this.minBasketCents = minBasketCents;
        this.maxDiscountCents = maxDiscountCents;
        this.perUserLimit = perUserLimit;
        this.startsAt = startsAt;
        this.endsAt = endsAt;
    }

    boolean liveAt(OffsetDateTime at) {
        return active
            && (startsAt == null || !at.isBefore(startsAt))
            && (endsAt == null || at.isBefore(endsAt));
    }

    /**
     * What this takes off a basket, or 0 if it doesn't qualify.
     *
     * <p>Never more than the food subtotal: the discount comes off the
     * merchant's side (see {@link CustomerOrder}), and a discount larger than
     * what the merchant is being paid would mean the platform funding someone
     * else's campaign.
     */
    int discountFor(int subtotalCents, int deliveryFeeCents) {
        if (subtotalCents < minBasketCents) return 0;
        int discount = switch (kind) {
            case PERCENT -> Math.floorDiv(subtotalCents * valueBps, 10_000);
            case FIXED -> amountCents;
            case FREE_DELIVERY -> deliveryFeeCents;
        };
        if (maxDiscountCents > 0) {
            discount = Math.min(discount, maxDiscountCents);
        }
        return Math.clamp(discount, 0, subtotalCents);
    }

    void deactivate() {
        this.active = false;
        this.updatedAt = OffsetDateTime.now();
    }

    UUID getId() {
        return id;
    }

    UUID getMerchantId() {
        return merchantId;
    }

    String getCode() {
        return code == null ? "" : code;
    }

    String getLabel() {
        return label;
    }

    Kind getKind() {
        return kind;
    }

    int getValueBps() {
        return valueBps;
    }

    int getAmountCents() {
        return amountCents;
    }

    int getMinBasketCents() {
        return minBasketCents;
    }

    int getMaxDiscountCents() {
        return maxDiscountCents;
    }

    int getPerUserLimit() {
        return perUserLimit;
    }

    boolean isActive() {
        return active;
    }

    OffsetDateTime getStartsAt() {
        return startsAt;
    }

    OffsetDateTime getEndsAt() {
        return endsAt;
    }

    enum Kind { PERCENT, FIXED, FREE_DELIVERY }
}
