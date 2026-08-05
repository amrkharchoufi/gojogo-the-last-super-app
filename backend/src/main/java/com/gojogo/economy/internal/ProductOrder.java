package com.gojogo.economy.internal;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * One checkout against one seller (SPECS §6: one cart per seller context).
 * Server-priced at placement, held in the buyer's escrow, settled when the
 * buyer confirms receipt — or when the auto-complete sweep decides they never
 * will (a shipped parcel is not the seller's hostage).
 *
 * <p>The state machine is four words, deliberately fewer than delivery's six:
 * {@code PLACED → SHIPPED → COMPLETED | CANCELLED}. There is no courier and no
 * kitchen — what happens between "posted" and "arrived" is a carrier's business,
 * and a status this system cannot observe is a status it must not claim.
 *
 * <p>Line rows snapshot name and price, so the catalog changing under an old
 * order changes nothing about what was bought.
 */
@Entity
@Table(name = "product_order", schema = "economy")
class ProductOrder {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "buyer_id", nullable = false)
    private UUID buyerId;

    @Column(name = "seller_id", nullable = false)
    private UUID sellerId;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private ProductOrderStatus status = ProductOrderStatus.PLACED;

    @Column(name = "subtotal_cents", nullable = false)
    private int subtotalCents;

    @Column(name = "discount_cents", nullable = false)
    private int discountCents;

    @Column(name = "shipping_cents", nullable = false)
    private int shippingCents;

    @Column(name = "tax_cents", nullable = false)
    private int taxCents;

    @Column(name = "total_cents", nullable = false)
    private int totalCents;

    @Column(name = "promotion_id")
    private UUID promotionId;

    @Column(name = "promotion_label")
    private String promotionLabel;

    @Enumerated(EnumType.STRING)
    @Column(name = "payment_status", nullable = false, length = 16)
    private PaymentState paymentStatus = PaymentState.NONE;

    /** The shipping address as one snapshot string — where this order goes,
     *  frozen at checkout. Empty for a digital order (M2). */
    @Column(name = "ship_to", nullable = false)
    private String shipTo = "";

    /** Whatever the seller wants the buyer to know about the parcel — a carrier
     *  and a tracking number, usually. Free text; this system doesn't pretend
     *  to integrate carriers. */
    @Column(name = "tracking_note", nullable = false)
    private String trackingNote = "";

    @Column(name = "placed_at", nullable = false)
    private OffsetDateTime placedAt = OffsetDateTime.now();

    @Column(name = "held_at")
    private OffsetDateTime heldAt;

    @Column(name = "shipped_at")
    private OffsetDateTime shippedAt;

    @Column(name = "completed_at")
    private OffsetDateTime completedAt;

    @Column(name = "cancelled_at")
    private OffsetDateTime cancelledAt;

    @Column(name = "settled_at")
    private OffsetDateTime settledAt;

    @OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.LAZY)
    private List<ProductOrderLine> lines = new ArrayList<>();

    protected ProductOrder() {
    }

    ProductOrder(UUID buyerId, UUID sellerId, String shipTo) {
        this.buyerId = buyerId;
        this.sellerId = sellerId;
        this.shipTo = shipTo == null ? "" : shipTo;
    }

    ProductOrderLine addLine(UUID productId, UUID variantId, String productName,
                             String variantLabel, long unitPriceCents, int quantity) {
        ProductOrderLine line = new ProductOrderLine(this, productId, variantId,
            productName, variantLabel, unitPriceCents, quantity);
        lines.add(line);
        return line;
    }

    void price(int subtotalCents, int discountCents, int shippingCents, int taxCents,
               UUID promotionId, String promotionLabel) {
        this.subtotalCents = subtotalCents;
        this.discountCents = discountCents;
        this.shippingCents = shippingCents;
        this.taxCents = taxCents;
        this.totalCents = subtotalCents - discountCents + shippingCents + taxCents;
        this.promotionId = promotionId;
        this.promotionLabel = promotionLabel;
    }

    void held(OffsetDateTime at) {
        this.paymentStatus = PaymentState.HELD;
        this.heldAt = at;
    }

    void shipped(String trackingNote, OffsetDateTime at) {
        this.status = ProductOrderStatus.SHIPPED;
        this.trackingNote = trackingNote == null ? "" : trackingNote;
        this.shippedAt = at;
    }

    void completed(OffsetDateTime at) {
        this.status = ProductOrderStatus.COMPLETED;
        this.completedAt = at;
    }

    void cancelled(OffsetDateTime at) {
        this.status = ProductOrderStatus.CANCELLED;
        this.cancelledAt = at;
    }

    void settled(OffsetDateTime at) {
        this.paymentStatus = PaymentState.SETTLED;
        this.settledAt = at;
    }

    void releasedFunds(OffsetDateTime at) {
        this.paymentStatus = PaymentState.RELEASED;
        this.settledAt = at;
    }

    UUID getId() {
        return id;
    }

    UUID getBuyerId() {
        return buyerId;
    }

    UUID getSellerId() {
        return sellerId;
    }

    ProductOrderStatus getStatus() {
        return status;
    }

    int getSubtotalCents() {
        return subtotalCents;
    }

    int getDiscountCents() {
        return discountCents;
    }

    int getShippingCents() {
        return shippingCents;
    }

    int getTaxCents() {
        return taxCents;
    }

    int getTotalCents() {
        return totalCents;
    }

    UUID getPromotionId() {
        return promotionId;
    }

    String getPromotionLabel() {
        return promotionLabel;
    }

    PaymentState getPaymentStatus() {
        return paymentStatus;
    }

    String getShipTo() {
        return shipTo;
    }

    String getTrackingNote() {
        return trackingNote;
    }

    OffsetDateTime getPlacedAt() {
        return placedAt;
    }

    OffsetDateTime getShippedAt() {
        return shippedAt;
    }

    OffsetDateTime getCompletedAt() {
        return completedAt;
    }

    OffsetDateTime getCancelledAt() {
        return cancelledAt;
    }

    List<ProductOrderLine> getLines() {
        return lines;
    }

    /**
     * Not named {@code PaymentStatus} — delivery already has that enum, and two
     * modules sharing a simple class name collide (PROGRESS incidents log).
     */
    enum PaymentState { NONE, HELD, SETTLED, RELEASED }
}
