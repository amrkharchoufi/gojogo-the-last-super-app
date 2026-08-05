package com.gojogo.services.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/** A certification paper — a private object key ({@code MediaDocumentApi}),
 *  never a public URL. The owner manages them; nothing renders them publicly. */
@Entity
@Table(name = "provider_document", schema = "services")
class ProviderDocument {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "provider_id", nullable = false)
    private UUID providerId;

    @Column(name = "object_key", nullable = false)
    private String objectKey;

    @Column(name = "label", nullable = false)
    private String label = "";

    @Column(name = "uploaded_at", nullable = false)
    private OffsetDateTime uploadedAt = OffsetDateTime.now();

    protected ProviderDocument() {
    }

    ProviderDocument(UUID providerId, String objectKey, String label) {
        this.providerId = providerId;
        this.objectKey = objectKey;
        this.label = label == null ? "" : label;
    }

    UUID getId() {
        return id;
    }

    UUID getProviderId() {
        return providerId;
    }

    String getObjectKey() {
        return objectKey;
    }

    String getLabel() {
        return label;
    }

    OffsetDateTime getUploadedAt() {
        return uploadedAt;
    }
}
