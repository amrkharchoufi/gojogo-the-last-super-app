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

/** One paper about one car. Stores the object key; never a URL. */
@Entity
@Table(name = "vehicle_document", schema = "partner")
class VehicleDocument {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "vehicle_id", nullable = false, updatable = false)
    private UUID vehicleId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 24)
    private VehicleDocumentKind kind;

    @Column(name = "object_key", nullable = false, length = 400)
    private String objectKey;

    @Column(name = "content_type", nullable = false, length = 80)
    private String contentType = "";

    @Column(name = "uploaded_at", nullable = false)
    private OffsetDateTime uploadedAt;

    protected VehicleDocument() {
    }

    VehicleDocument(UUID vehicleId, VehicleDocumentKind kind, String objectKey,
                    String contentType) {
        this.vehicleId = vehicleId;
        this.kind = kind;
        this.objectKey = objectKey;
        this.contentType = contentType == null ? "" : contentType;
        this.uploadedAt = OffsetDateTime.now();
    }

    void replaceWith(String objectKey, String contentType) {
        this.objectKey = objectKey;
        this.contentType = contentType == null ? "" : contentType;
        this.uploadedAt = OffsetDateTime.now();
    }

    UUID getId() { return id; }
    UUID getVehicleId() { return vehicleId; }
    VehicleDocumentKind getKind() { return kind; }
    String getObjectKey() { return objectKey; }
    String getContentType() { return contentType; }
    OffsetDateTime getUploadedAt() { return uploadedAt; }
}
