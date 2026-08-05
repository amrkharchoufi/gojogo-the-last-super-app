package com.gojogo.delivery.internal;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Embeddable;
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
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * A complaint about a delivered order (Phase 4 M6, SPECS §5).
 *
 * <p>The thing that has been missing since money started moving: cancelling
 * before delivery releases the hold, but a settled order had <em>no</em> route
 * back at all. Everything about the shape here follows from the fact that it is
 * argued after the money has already been split — see {@link DisputePayer}.
 *
 * <p><b>One per order, deliberately.</b> Not one per kitchen, which reads
 * better on a multi-merchant order right up until two operators open the two
 * disputes and refund the same missing pizza twice. A dispute is a conversation
 * about an order; it names a sub-order when the complaint is about one kitchen's
 * bag, and the operator refunds once.
 */
@Entity
@Table(name = "dispute", schema = "delivery")
class Dispute {

    @Id
    @GeneratedValue
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "order_id", nullable = false)
    private CustomerOrder order;

    /**
     * Which kitchen's bag, when the complaint is about one. Null for a
     * complaint about the order as a whole — a delivery that never arrived is
     * not any particular restaurant's fault. A MERCHANT-funded refund requires
     * this, because "the merchant pays" means nothing on an order spanning
     * three of them.
     */
    @Column(name = "sub_order_id")
    private UUID subOrderId;

    /** The customer, copied rather than read through the order: this row
     *  outlives an order's usefulness and is read by an operator who should not
     *  have to join to find out whose complaint it is. */
    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Enumerated(EnumType.STRING)
    @Column(name = "reason", nullable = false)
    private DisputeReason reason;

    /** What they actually said. The reason is for sorting; this is what is
     *  read. */
    @Column(name = "note", nullable = false)
    private String note = "";

    @Enumerated(EnumType.STRING)
    @Column(name = "state", nullable = false)
    private DisputeState state = DisputeState.OPEN;

    /**
     * What the customer says is wrong, priced from the order's own lines.
     *
     * <p>Kept as a number on the row rather than recomputed, because the lines
     * it came from are copies too (an order line copies the menu price at order
     * time for the same reason). It is what an operator starts from, never a
     * cap: somebody who says two of six items are missing may be owed more than
     * two items' worth, and may be owed nothing.
     */
    @Column(name = "claimed_cents", nullable = false)
    private int claimedCents;

    @ElementCollection(fetch = FetchType.LAZY)
    @CollectionTable(name = "dispute_item", schema = "delivery",
        joinColumns = @JoinColumn(name = "dispute_id"))
    private List<DisputedItem> items = new ArrayList<>();

    /** Private object keys, never URLs and always ones the server minted —
     *  the same posture the drop-off proof photo takes, for the same kind of
     *  picture. */
    @ElementCollection(fetch = FetchType.LAZY)
    @CollectionTable(name = "dispute_photo", schema = "delivery",
        joinColumns = @JoinColumn(name = "dispute_id"))
    @Column(name = "object_key", nullable = false)
    private List<String> photoKeys = new ArrayList<>();

    // MARK: The resolution

    @Column(name = "refund_cents", nullable = false)
    private int refundCents;

    @Enumerated(EnumType.STRING)
    @Column(name = "payer")
    private DisputePayer payer;

    /** Why, in words the customer reads. A rejection without one is a dispute
     *  somebody chases forever. */
    @Column(name = "resolution_note", nullable = false)
    private String resolutionNote = "";

    /** Which operator, as the admin surface names them — a JWT identity or the
     *  break-glass token. The same string the moderation queue records. */
    @Column(name = "resolved_by", nullable = false)
    private String resolvedBy = "";

    @Column(name = "resolved_at")
    private OffsetDateTime resolvedAt;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Version
    @Column(name = "version", nullable = false)
    private int version;

    protected Dispute() {
    }

    Dispute(CustomerOrder order, UUID subOrderId, DisputeReason reason, String note) {
        this.order = order;
        this.subOrderId = subOrderId;
        this.userId = order.getUserId();
        this.reason = reason;
        this.note = note == null ? "" : note.trim();
    }

    void claim(List<DisputedItem> claimed) {
        this.items.clear();
        this.items.addAll(claimed);
        this.claimedCents = claimed.stream()
            .mapToInt(item -> item.getUnitPriceCents() * item.getQty())
            .sum();
    }

    void photographedAt(String objectKey) {
        if (objectKey != null && !photoKeys.contains(objectKey)) {
            photoKeys.add(objectKey);
        }
    }

    void refunded(int cents, DisputePayer payer, String note, String by, OffsetDateTime at) {
        this.state = DisputeState.RESOLVED_REFUND;
        this.refundCents = cents;
        this.payer = payer;
        this.resolutionNote = note == null ? "" : note.trim();
        this.resolvedBy = by == null ? "" : by;
        this.resolvedAt = at;
    }

    void rejected(String note, String by, OffsetDateTime at) {
        this.state = DisputeState.RESOLVED_REJECTED;
        this.resolutionNote = note == null ? "" : note.trim();
        this.resolvedBy = by == null ? "" : by;
        this.resolvedAt = at;
    }

    UUID getId() {
        return id;
    }

    CustomerOrder getOrder() {
        return order;
    }

    UUID getSubOrderId() {
        return subOrderId;
    }

    UUID getUserId() {
        return userId;
    }

    DisputeReason getReason() {
        return reason;
    }

    String getNote() {
        return note;
    }

    DisputeState getState() {
        return state;
    }

    int getClaimedCents() {
        return claimedCents;
    }

    List<DisputedItem> getItems() {
        return items;
    }

    List<String> getPhotoKeys() {
        return photoKeys;
    }

    int getRefundCents() {
        return refundCents;
    }

    DisputePayer getPayer() {
        return payer;
    }

    String getResolutionNote() {
        return resolutionNote;
    }

    String getResolvedBy() {
        return resolvedBy;
    }

    OffsetDateTime getResolvedAt() {
        return resolvedAt;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    /**
     * One line of what the customer says was wrong. The name and price are
     * copied off the order line, exactly as the order line copied them off the
     * menu — a complaint has to keep saying what it was about after the
     * restaurant renames the dish.
     */
    @Embeddable
    static class DisputedItem {

        @Column(name = "menu_item_id", nullable = false)
        private UUID menuItemId;

        @Column(name = "name", nullable = false)
        private String name;

        @Column(name = "unit_price_cents", nullable = false)
        private int unitPriceCents;

        @Column(name = "qty", nullable = false)
        private int qty;

        protected DisputedItem() {
        }

        DisputedItem(UUID menuItemId, String name, int unitPriceCents, int qty) {
            this.menuItemId = menuItemId;
            this.name = name;
            this.unitPriceCents = unitPriceCents;
            this.qty = qty;
        }

        UUID getMenuItemId() {
            return menuItemId;
        }

        String getName() {
            return name;
        }

        int getUnitPriceCents() {
            return unitPriceCents;
        }

        int getQty() {
            return qty;
        }
    }
}
