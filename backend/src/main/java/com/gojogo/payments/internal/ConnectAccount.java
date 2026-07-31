package com.gojogo.payments.internal;

import com.gojogo.payments.OwnerKind;
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
 * A payee's Stripe Connect account — the only route money takes out of the
 * platform. One per (owner kind, owner id): a merchant, and later a driver,
 * courier, seller or provider.
 *
 * <p>Stripe's two gates are mirrored here so a payout can be refused with a
 * reason the payee can act on, rather than by attempting a transfer and reading
 * the failure: {@code detailsSubmitted} (they finished the form) and
 * {@code payoutsEnabled} (Stripe is willing to pay them, which is a separate and
 * later thing — verification can still be running).
 */
@Entity
@Table(name = "connect_account", schema = "payments")
class ConnectAccount {

    @Id
    @GeneratedValue
    private UUID id;

    @Enumerated(EnumType.STRING)
    @Column(name = "owner_kind", nullable = false)
    private OwnerKind ownerKind;

    @Column(name = "owner_id", nullable = false)
    private UUID ownerId;

    @Column(name = "stripe_account_id", nullable = false)
    private String stripeAccountId;

    @Column(name = "details_submitted", nullable = false)
    private boolean detailsSubmitted;

    @Column(name = "payouts_enabled", nullable = false)
    private boolean payoutsEnabled;

    @Column(name = "requirements_note", nullable = false)
    private String requirementsNote = "";

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt = OffsetDateTime.now();

    protected ConnectAccount() {
    }

    ConnectAccount(OwnerKind ownerKind, UUID ownerId, String stripeAccountId) {
        this.ownerKind = ownerKind;
        this.ownerId = ownerId;
        this.stripeAccountId = stripeAccountId;
    }

    void sync(boolean detailsSubmitted, boolean payoutsEnabled, String requirementsNote) {
        this.detailsSubmitted = detailsSubmitted;
        this.payoutsEnabled = payoutsEnabled;
        this.requirementsNote = requirementsNote == null ? ""
            : requirementsNote.substring(0, Math.min(requirementsNote.length(), 400));
        this.updatedAt = OffsetDateTime.now();
    }

    String getStripeAccountId() {
        return stripeAccountId;
    }

    boolean isDetailsSubmitted() {
        return detailsSubmitted;
    }

    boolean isPayoutsEnabled() {
        return payoutsEnabled;
    }

    String getRequirementsNote() {
        return requirementsNote;
    }
}
