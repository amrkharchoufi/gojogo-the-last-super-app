package com.gojogo.partner.internal;

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
 * One uploaded identity or business paper.
 *
 * <p>What's stored is the S3 <em>object key</em>, not a URL, and the object sits
 * outside the world-readable {@code media/} prefix. Handing this row's contents
 * to a client grants nothing; a reviewer gets a 10-minute presigned GET minted
 * per view.
 */
@Entity
@Table(name = "partner_document", schema = "partner")
class PartnerDocument {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "account_id", nullable = false, updatable = false)
    private UUID accountId;

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false, updatable = false)
    private DocumentKind kind;

    @Column(name = "object_key", nullable = false)
    private String objectKey;

    @Column(name = "content_type", nullable = false)
    private String contentType = "";

    @Column(name = "uploaded_at", nullable = false)
    private OffsetDateTime uploadedAt = OffsetDateTime.now();

    protected PartnerDocument() {
    }

    PartnerDocument(UUID accountId, DocumentKind kind, String objectKey, String contentType) {
        this.accountId = accountId;
        this.kind = kind;
        this.objectKey = objectKey;
        this.contentType = contentType == null ? "" : contentType;
    }

    /** Replaces the file behind this kind — a re-uploaded, legible ID card. */
    void replaceWith(String objectKey, String contentType) {
        this.objectKey = objectKey;
        this.contentType = contentType == null ? "" : contentType;
        this.uploadedAt = OffsetDateTime.now();
    }

    UUID getId() { return id; }
    UUID getAccountId() { return accountId; }
    DocumentKind getKind() { return kind; }
    String getObjectKey() { return objectKey; }
    String getContentType() { return contentType; }
    OffsetDateTime getUploadedAt() { return uploadedAt; }
}
