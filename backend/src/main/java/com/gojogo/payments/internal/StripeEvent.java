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
 * <p><b>Named for its vendor, not its role.</b> The obvious name —
 * {@code ProviderEvent}, matching the table — is already taken by the KYC
 * module, and two same-named classes in different packages collide twice over:
 * on the Spring bean name of their repositories, and on Hibernate's entity name.
 * The first of those took a production deploy down (see the incidents log); the
 * table is still {@code payments.provider_event}, because the collision is a
 * Java-side one.
 *
 * <p>The row <em>is</em> the lock: inserting it is what claims the delivery, so
 * two concurrent retries cannot both decide they are first.
 */
@Entity
@Table(name = "provider_event", schema = "payments")
class StripeEvent {

    @Id
    @Column(name = "id", nullable = false)
    private String id;

    @Column(name = "type", nullable = false)
    private String type = "";

    @Column(name = "received_at", nullable = false)
    private OffsetDateTime receivedAt = OffsetDateTime.now();

    protected StripeEvent() {
    }

    StripeEvent(String id, String type) {
        this.id = id;
        this.type = type == null ? "" : type;
    }
}
