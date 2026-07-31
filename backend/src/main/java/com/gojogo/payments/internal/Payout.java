package com.gojogo.payments.internal;

import com.gojogo.payments.OwnerKind;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/** One attempt to send money to a connected account. */
@Entity
@Table(name = "payout", schema = "payments")
class Payout {

    /** Assigned rather than generated, for the same reason
     *  {@link StripePayment}'s is: the id goes into the transfer's metadata, so
     *  it must exist before Stripe is called. */
    @Id
    @Column(name = "id", nullable = false)
    private UUID id = UUID.randomUUID();

    @Enumerated(EnumType.STRING)
    @Column(name = "owner_kind", nullable = false)
    private OwnerKind ownerKind;

    @Column(name = "owner_id", nullable = false)
    private UUID ownerId;

    /** The person who asked — a merchant's owner today, an operator in
     *  GoJoAdmin later. Also who gets told when it lands. */
    @Column(name = "requested_by")
    private UUID requestedBy;

    @Column(name = "amount_minor", nullable = false)
    private long amountMinor;

    @Column(name = "currency", nullable = false)
    private String currency;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private Status status = Status.REQUESTED;

    @Column(name = "stripe_transfer_id")
    private String stripeTransferId;

    @Column(name = "failure_reason", nullable = false)
    private String failureReason = "";

    @Column(name = "ledger_entry_id")
    private UUID ledgerEntryId;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt = OffsetDateTime.now();

    protected Payout() {
    }

    Payout(OwnerKind ownerKind, UUID ownerId, UUID requestedBy, long amountMinor, String currency) {
        this.ownerKind = ownerKind;
        this.ownerId = ownerId;
        this.requestedBy = requestedBy;
        this.amountMinor = amountMinor;
        this.currency = currency;
    }

    /** The balance has moved; the transfer hasn't been attempted yet. Status
     *  stays REQUESTED — that is the whole point of the two-phase order. */
    void debited(UUID ledgerEntryId) {
        this.ledgerEntryId = ledgerEntryId;
        this.updatedAt = OffsetDateTime.now();
    }

    void sent(String stripeTransferId) {
        this.status = Status.SENT;
        this.stripeTransferId = stripeTransferId;
        this.updatedAt = OffsetDateTime.now();
    }

    void failed(String reason) {
        this.status = Status.FAILED;
        this.failureReason = reason == null ? ""
            : reason.substring(0, Math.min(reason.length(), 300));
        this.updatedAt = OffsetDateTime.now();
    }

    UUID getId() {
        return id;
    }

    OwnerKind getOwnerKind() {
        return ownerKind;
    }

    UUID getOwnerId() {
        return ownerId;
    }

    UUID getRequestedBy() {
        return requestedBy;
    }

    long getAmountMinor() {
        return amountMinor;
    }

    String getCurrency() {
        return currency;
    }

    Status getStatus() {
        return status;
    }

    String getFailureReason() {
        return failureReason;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    enum Status { REQUESTED, SENT, FAILED }
}
