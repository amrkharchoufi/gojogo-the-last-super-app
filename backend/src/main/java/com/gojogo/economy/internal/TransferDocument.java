package com.gojogo.economy.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/** One piece of a transfer's paperwork — an object key in the private prefix,
 *  read through short-lived signed GETs by the parties and the reviewer. */
@Entity
@Table(name = "transfer_document", schema = "economy")
class TransferDocument {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "transfer_id", nullable = false)
    private UUID transferId;

    @Column(name = "object_key", nullable = false)
    private String objectKey;

    @Column(name = "label", nullable = false)
    private String label = "";

    @Column(name = "uploaded_at", nullable = false)
    private OffsetDateTime uploadedAt = OffsetDateTime.now();

    protected TransferDocument() {
    }

    TransferDocument(UUID transferId, String objectKey, String label) {
        this.transferId = transferId;
        this.objectKey = objectKey;
        this.label = label == null ? "" : label;
    }

    UUID getId() {
        return id;
    }

    UUID getTransferId() {
        return transferId;
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
