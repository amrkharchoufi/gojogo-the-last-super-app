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
 * One buyer's attempt to take ownership of a numbered thing (SPECS §6).
 *
 * <p>The state machine is the spec's, and its spine is the human checkpoint:
 * money is held before the paperwork is looked at, and moves only after a
 * person has confirmed the documents — the same posture as KYC review. Either
 * side can walk away before that confirmation for a full refund; after it, the
 * thing is presumed changing hands and only the buyer's confirmation ends it.
 */
@Entity
@Table(name = "ownership_transfer", schema = "economy")
class OwnershipTransfer {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "listing_id", nullable = false)
    private UUID listingId;

    @Column(name = "seller_id", nullable = false)
    private UUID sellerId;

    @Column(name = "buyer_id", nullable = false)
    private UUID buyerId;

    @Enumerated(EnumType.STRING)
    @Column(name = "state", nullable = false, length = 24)
    private TransferState state = TransferState.INQUIRY;

    /** Agreed at acceptance, never edited after — the escrow is exactly this. */
    @Column(name = "price_cents")
    private Long priceCents;

    /** Above the CONFIG wallet cap: escrow refused, operator settles by hand. */
    @Column(name = "flagged_manual", nullable = false)
    private boolean flaggedManual;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "accepted_at")
    private OffsetDateTime acceptedAt;

    @Column(name = "paid_at")
    private OffsetDateTime paidAt;

    @Column(name = "docs_confirmed_at")
    private OffsetDateTime docsConfirmedAt;

    /** Who looked at the paperwork — an attribution, like a KYC decision. */
    @Column(name = "docs_confirmed_by")
    private String docsConfirmedBy;

    @Column(name = "transferred_at")
    private OffsetDateTime transferredAt;

    @Column(name = "released_at")
    private OffsetDateTime releasedAt;

    @Column(name = "cancelled_at")
    private OffsetDateTime cancelledAt;

    @Column(name = "cancel_note", nullable = false)
    private String cancelNote = "";

    protected OwnershipTransfer() {
    }

    OwnershipTransfer(UUID listingId, UUID sellerId, UUID buyerId) {
        this.listingId = listingId;
        this.sellerId = sellerId;
        this.buyerId = buyerId;
    }

    void accepted(long priceCents, OffsetDateTime at) {
        this.state = TransferState.OFFER_ACCEPTED;
        this.priceCents = priceCents;
        this.acceptedAt = at;
    }

    void paid(OffsetDateTime at) {
        this.state = TransferState.PAYMENT_HELD;
        this.paidAt = at;
    }

    void flagManual() {
        this.flaggedManual = true;
    }

    void docsConfirmed(String by, OffsetDateTime at) {
        this.state = TransferState.DOCS_CONFIRMED;
        this.docsConfirmedBy = by;
        this.docsConfirmedAt = at;
    }

    void transferred(OffsetDateTime at) {
        this.state = TransferState.TRANSFERRED;
        this.transferredAt = at;
    }

    void released(OffsetDateTime at) {
        this.state = TransferState.RELEASED;
        this.releasedAt = at;
    }

    void cancelled(String note, OffsetDateTime at) {
        this.state = TransferState.CANCELLED;
        this.cancelNote = note == null ? "" : note;
        this.cancelledAt = at;
    }

    boolean isParty(UUID userId) {
        return buyerId.equals(userId) || sellerId.equals(userId);
    }

    UUID getId() {
        return id;
    }

    UUID getListingId() {
        return listingId;
    }

    UUID getSellerId() {
        return sellerId;
    }

    UUID getBuyerId() {
        return buyerId;
    }

    TransferState getState() {
        return state;
    }

    Long getPriceCents() {
        return priceCents;
    }

    boolean isFlaggedManual() {
        return flaggedManual;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    OffsetDateTime getAcceptedAt() {
        return acceptedAt;
    }

    OffsetDateTime getPaidAt() {
        return paidAt;
    }

    OffsetDateTime getDocsConfirmedAt() {
        return docsConfirmedAt;
    }

    String getDocsConfirmedBy() {
        return docsConfirmedBy;
    }

    OffsetDateTime getTransferredAt() {
        return transferredAt;
    }

    OffsetDateTime getReleasedAt() {
        return releasedAt;
    }

    OffsetDateTime getCancelledAt() {
        return cancelledAt;
    }

    String getCancelNote() {
        return cancelNote;
    }
}
