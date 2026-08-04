package com.gojogo.delivery.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * One merchant's slice of a {@link CustomerOrder} (Phase 4 M3).
 *
 * <p>What lives here is exactly what is one restaurant's business: their
 * basket's money, their prep clock, their pickup code, their reason if their
 * slice ended early. The parent keeps everything that is the <em>order's</em> —
 * the address, the courier, the six statuses, the delivery PIN (one door), and
 * the totals the hold was taken for.
 *
 * <p>The pickup code moved down from the order, per SPECS §5: a courier
 * collecting three bags proves each counter separately, and a code that could
 * open all three would prove presence at none of them.
 */
@Entity
@Table(name = "sub_order", schema = "delivery")
class SubOrder {

    @Id
    @GeneratedValue
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "order_id", nullable = false)
    private CustomerOrder order;

    @Column(name = "merchant_id", nullable = false)
    private UUID merchantId;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private SubOrderStatus status = SubOrderStatus.CONFIRMED;

    @Column(name = "subtotal_cents", nullable = false)
    private int subtotalCents;

    @Column(name = "delivery_fee_cents", nullable = false)
    private int deliveryFeeCents;

    @Column(name = "discount_cents", nullable = false)
    private int discountCents;

    @Column(name = "promotion_id")
    private UUID promotionId;

    @Column(name = "promotion_code", nullable = false)
    private String promotionCode = "";

    @Column(name = "pickup_code", nullable = false)
    private String pickupCode = "";

    @Column(name = "prep_minutes")
    private Integer prepMinutes;

    @Column(name = "accepted_at")
    private OffsetDateTime acceptedAt;

    @Column(name = "ready_at")
    private OffsetDateTime readyAt;

    /**
     * When this kitchen actually said the food was ready, as opposed to when
     * they guessed it would be (Phase 4 M4).
     *
     * <p>Kept beside {@link #readyAt} rather than overwriting it, because for a
     * collection the two are different facts to a different person: the
     * estimate is when to set off, and this is "it is on the counter, come and
     * get it" — the push nobody can send from an estimate. Still a timestamp
     * and still not a status, which is the decision M1 made about readiness and
     * this milestone found no reason to reopen.
     */
    @Column(name = "ready_marked_at")
    private OffsetDateTime readyMarkedAt;

    @Column(name = "collected_at")
    private OffsetDateTime collectedAt;

    /**
     * Where the customer walks to, copied at placement — the merchant's own
     * pickup line, or their address when they have not written one. A copy for
     * the same reason the delivery address on the parent is one: a receipt
     * should not be rewritten by a merchant editing their row six months later.
     * Blank on every delivery order, where the question does not arise.
     */
    @Column(name = "pickup_address", nullable = false)
    private String pickupAddress = "";

    @Column(name = "cancel_reason", nullable = false)
    private String cancelReason = "";

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    @Version
    @Column(name = "version", nullable = false)
    private int version;

    protected SubOrder() {
    }

    SubOrder(CustomerOrder order, UUID merchantId, int subtotalCents, int deliveryFeeCents,
             int discountCents, UUID promotionId, String promotionCode, int sortOrder) {
        this.order = order;
        this.merchantId = merchantId;
        this.subtotalCents = subtotalCents;
        this.deliveryFeeCents = deliveryFeeCents;
        this.discountCents = discountCents;
        this.promotionId = promotionId;
        this.promotionCode = promotionCode == null ? "" : promotionCode;
        this.sortOrder = sortOrder;
    }

    /** This restaurant took their slice, and said how long they need. */
    void accepted(OffsetDateTime at, int prepMinutes) {
        this.status = SubOrderStatus.PREPARING;
        this.acceptedAt = at;
        this.prepMinutes = prepMinutes;
        this.readyAt = at.plusMinutes(prepMinutes);
    }

    /** Guarded like the parent's PIN: a retried accept must not change a number
     *  a restaurant has already read aloud. */
    void mintPickupCode(String code) {
        if (pickupCode.isBlank()) this.pickupCode = code;
    }

    void readyNow(OffsetDateTime at) {
        this.readyAt = at;
        this.readyMarkedAt = at;
    }

    /** Where this slice is collected from — set at placement for a pickup. */
    void collectFrom(String address) {
        this.pickupAddress = address == null ? "" : address;
    }

    void collected(OffsetDateTime at) {
        this.status = SubOrderStatus.COLLECTED;
        this.collectedAt = at;
    }

    void deliveredWithParent() {
        this.status = SubOrderStatus.DELIVERED;
    }

    void cancelledBecause(String reason) {
        this.status = SubOrderStatus.CANCELLED;
        this.cancelReason = reason == null ? "" : reason;
    }

    /** What a cancellation of this slice gives back: the food and this
     *  merchant's delivery fee. The service fee and the tip are the order's. */
    int shareCents() {
        return subtotalCents - discountCents + deliveryFeeCents;
    }

    UUID getId() {
        return id;
    }

    CustomerOrder getOrder() {
        return order;
    }

    UUID getMerchantId() {
        return merchantId;
    }

    SubOrderStatus getStatus() {
        return status;
    }

    int getSubtotalCents() {
        return subtotalCents;
    }

    int getDeliveryFeeCents() {
        return deliveryFeeCents;
    }

    int getDiscountCents() {
        return discountCents;
    }

    UUID getPromotionId() {
        return promotionId;
    }

    String getPromotionCode() {
        return promotionCode;
    }

    String getPickupCode() {
        return pickupCode;
    }

    Integer getPrepMinutes() {
        return prepMinutes;
    }

    OffsetDateTime getAcceptedAt() {
        return acceptedAt;
    }

    OffsetDateTime getReadyAt() {
        return readyAt;
    }

    OffsetDateTime getReadyMarkedAt() {
        return readyMarkedAt;
    }

    String getPickupAddress() {
        return pickupAddress;
    }

    OffsetDateTime getCollectedAt() {
        return collectedAt;
    }

    String getCancelReason() {
        return cancelReason;
    }

    int getSortOrder() {
        return sortOrder;
    }
}
