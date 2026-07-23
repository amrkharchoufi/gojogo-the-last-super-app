package com.gojogo.media.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * One presigned upload. The S3 object key is the identity. {@code referencedAt}
 * is null until a module reports the URL as used; the sweep only ever touches
 * rows that stay null past the grace period.
 */
@Entity
@Table(name = "upload_object", schema = "media")
class UploadObject {

    @Id
    @Column(name = "object_key")
    private String objectKey;

    @Column(name = "profile_id", nullable = false)
    private UUID profileId;

    @Column(name = "content_type", nullable = false)
    private String contentType;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    @Column(name = "referenced_at")
    private OffsetDateTime referencedAt;

    protected UploadObject() {
    }

    UploadObject(String objectKey, UUID profileId, String contentType, OffsetDateTime createdAt) {
        this.objectKey = objectKey;
        this.profileId = profileId;
        this.contentType = contentType;
        this.createdAt = createdAt;
    }

    String getObjectKey() { return objectKey; }
    UUID getProfileId() { return profileId; }
    String getContentType() { return contentType; }
    OffsetDateTime getCreatedAt() { return createdAt; }
    OffsetDateTime getReferencedAt() { return referencedAt; }
}
