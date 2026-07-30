package com.gojogo.kyc.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;

/**
 * One webhook delivery, kept only so the next copy of it can be ignored.
 *
 * <p>Sumsub retries anything that isn't a 2xx, and a duplicated
 * {@code applicantReviewed} would re-publish {@link com.gojogo.kyc.IdentityVerified}
 * — which flips a partner's badge and fires a push. The row <em>is</em> the
 * lock: inserting it under the primary key is what claims a delivery, so two
 * concurrent retries cannot both win.
 */
@Entity
@Table(name = "provider_event", schema = "kyc")
class ProviderEvent {

    /** The vendor's delivery id, straight from the payload. */
    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private String id;

    @Column(name = "type", nullable = false)
    private String type = "";

    @Column(name = "applicant_id")
    private String applicantId;

    @Column(name = "received_at", nullable = false)
    private OffsetDateTime receivedAt = OffsetDateTime.now();

    protected ProviderEvent() {
    }

    ProviderEvent(String id, String type, String applicantId) {
        this.id = id;
        this.type = type == null ? "" : type;
        this.applicantId = applicantId;
    }
}
