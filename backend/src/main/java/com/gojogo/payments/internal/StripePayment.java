package com.gojogo.payments.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * One card top-up, mirroring a Stripe Checkout session.
 *
 * <p>Created when the customer asks for a payment link; completed when Stripe
 * says, over a signed webhook, that the session was paid. Never completed by the
 * browser coming back to a success URL — that proves a browser visited a URL and
 * nothing else, and it is the single most common way a wallet gets credited for
 * a payment that never happened.
 */
@Entity
@Table(name = "stripe_payment", schema = "payments")
class StripePayment {

    /**
     * Assigned, not generated: the id goes into the Checkout session's metadata,
     * so it has to exist before Stripe is called and therefore before the row is
     * written. (Spring Data reads a non-null id as "not new" and issues a merge,
     * which costs one extra SELECT on a path taken once per top-up — a fair
     * price for not having to invent a placeholder session id.)
     */
    @Id
    @Column(name = "id", nullable = false)
    private UUID id = UUID.randomUUID();

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "purpose", nullable = false)
    private String purpose = "TOPUP";

    @Column(name = "session_id", nullable = false)
    private String sessionId;

    @Column(name = "payment_intent_id")
    private String paymentIntentId;

    @Column(name = "amount_minor", nullable = false)
    private long amountMinor;

    @Column(name = "currency", nullable = false)
    private String currency;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private Status status = Status.CREATED;

    @Column(name = "checkout_url")
    private String checkoutUrl;

    @Column(name = "ledger_entry_id")
    private UUID ledgerEntryId;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt = OffsetDateTime.now();

    protected StripePayment() {
    }

    StripePayment(UUID id, UUID userId, String sessionId, String checkoutUrl,
                  long amountMinor, String currency) {
        this.id = id;
        this.userId = userId;
        this.sessionId = sessionId;
        this.checkoutUrl = checkoutUrl;
        this.amountMinor = amountMinor;
        this.currency = currency;
    }

    void succeeded(String paymentIntentId, UUID ledgerEntryId) {
        this.status = Status.SUCCEEDED;
        this.paymentIntentId = paymentIntentId;
        this.ledgerEntryId = ledgerEntryId;
        this.updatedAt = OffsetDateTime.now();
    }

    void closed(Status terminal) {
        this.status = terminal;
        this.updatedAt = OffsetDateTime.now();
    }

    boolean isPending() {
        return status == Status.CREATED;
    }

    UUID getId() {
        return id;
    }

    UUID getUserId() {
        return userId;
    }

    String getSessionId() {
        return sessionId;
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

    String getCheckoutUrl() {
        return checkoutUrl;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    enum Status { CREATED, SUCCEEDED, FAILED, EXPIRED }
}
