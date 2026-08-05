package com.gojogo.economy.internal;

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
 * The file behind a DIGITAL product — an object key in the private prefix
 * ({@code MediaDocumentApi}), never a public URL. What a purchase grants is
 * this asset's {@link EntitlementKind}.
 */
@Entity
@Table(name = "digital_asset", schema = "economy")
class DigitalAsset {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "product_id", nullable = false, unique = true)
    private UUID productId;

    @Column(name = "object_key", nullable = false)
    private String objectKey;

    @Column(name = "file_name", nullable = false)
    private String fileName = "";

    @Column(name = "content_type", nullable = false)
    private String contentType = "application/octet-stream";

    @Enumerated(EnumType.STRING)
    @Column(name = "entitlement_kind", nullable = false, length = 16)
    private EntitlementKind entitlementKind = EntitlementKind.DOWNLOAD;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    protected DigitalAsset() {
    }

    DigitalAsset(UUID productId, String objectKey, String fileName, String contentType,
                 EntitlementKind entitlementKind) {
        this.productId = productId;
        this.objectKey = objectKey;
        this.fileName = fileName == null ? "" : fileName;
        this.contentType = contentType == null || contentType.isBlank()
            ? "application/octet-stream" : contentType;
        this.entitlementKind = entitlementKind;
    }

    void replace(String objectKey, String fileName, String contentType,
                 EntitlementKind entitlementKind) {
        this.objectKey = objectKey;
        this.fileName = fileName == null ? "" : fileName;
        this.contentType = contentType == null || contentType.isBlank()
            ? "application/octet-stream" : contentType;
        this.entitlementKind = entitlementKind;
    }

    UUID getProductId() {
        return productId;
    }

    String getObjectKey() {
        return objectKey;
    }

    String getFileName() {
        return fileName;
    }

    String getContentType() {
        return contentType;
    }

    EntitlementKind getEntitlementKind() {
        return entitlementKind;
    }
}
