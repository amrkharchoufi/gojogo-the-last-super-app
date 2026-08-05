package com.gojogo.economy.internal;

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
 * SPECS §6's shared promotion shape, economy's copy — the second instance after
 * {@code delivery}'s. Applied server-side at pricing time, because a discount
 * the client computed is a discount the client chose.
 *
 * <p>{@code FREE_SHIPPING} is the fee-line discount, the same mechanism as
 * delivery's {@code FREE_DELIVERY} — and gets the same guard: it is refused by
 * name on a basket whose shipping is already zero, rather than left to be a
 * silent no-op that one day becomes money off goods.
 *
 * <p>Not named {@code Promotion}: delivery already has that entity, and two
 * modules sharing a simple class name collide on both the Spring bean name and
 * Hibernate's entity name (PROGRESS incidents log).
 */
@Entity
@Table(name = "product_promotion", schema = "economy")
class ProductPromotion {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "seller_id", nullable = false)
    private UUID sellerId;

    /** Null means automatic — applies to any qualifying basket with nothing to
     *  type. Stored upper-cased, matched case-insensitively. */
    @Column(name = "code")
    private String code;

    @Column(name = "label", nullable = false)
    private String label = "";

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false, length = 16)
    private Kind kind;

    @Column(name = "value_bps", nullable = false)
    private int valueBps;

    @Column(name = "amount_cents", nullable = false)
    private int amountCents;

    @Column(name = "min_basket_cents", nullable = false)
    private int minBasketCents;

    /** 0 = uncapped. An uncapped percentage is how a seller accidentally gives
     *  away $80 on one large order. */
    @Column(name = "max_discount_cents", nullable = false)
    private int maxDiscountCents;

    /** 0 = unlimited, counted from {@code product_promotion_redemption}. */
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

    protected ProductPromotion() {
    }

    ProductPromotion(UUID sellerId, String code, String label, Kind kind, int valueBps,
                     int amountCents, int minBasketCents, int maxDiscountCents,
                     int perUserLimit, OffsetDateTime startsAt, OffsetDateTime endsAt) {
        this.sellerId = sellerId;
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
     * What this takes off a basket, or 0 if it doesn't qualify. Never more than
     * the goods subtotal: the discount comes off the seller's side, and a bigger
     * one would mean the platform funding somebody else's campaign.
     */
    int discountFor(int subtotalCents, int shippingCents) {
        if (subtotalCents < minBasketCents) return 0;
        int discount = switch (kind) {
            case PERCENT -> Math.floorDiv(subtotalCents * valueBps, 10_000);
            case FIXED -> amountCents;
            case FREE_SHIPPING -> shippingCents;
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

    UUID getSellerId() {
        return sellerId;
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

    enum Kind { PERCENT, FIXED, FREE_SHIPPING }
}
