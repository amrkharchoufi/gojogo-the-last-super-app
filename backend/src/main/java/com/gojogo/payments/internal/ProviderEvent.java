package com.gojogo.payments.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;

/**
 * A webhook delivery we have already handled — the same shape
 * {@code kyc.provider_event} has, for the same reason. Stripe retries anything
 * non-2xx, and a replayed {@code checkout.session.completed} must not credit a
 * wallet twice.
 *
 * <p>The row <em>is</em> the lock: inserting it is what claims the delivery, so
 * two concurrent retries cannot both decide they are first.
 */
@Entity
@Table(name = "provider_event", schema = "payments")
class ProviderEvent {

    @Id
    @Column(name = "id", nullable = false)
    private String id;

    @Column(name = "type", nullable = false)
    private String type = "";

    @Column(name = "received_at", nullable = false)
    private OffsetDateTime receivedAt = OffsetDateTime.now();

    protected ProviderEvent() {
    }

    ProviderEvent(String id, String type) {
        this.id = id;
        this.type = type == null ? "" : type;
    }
}
