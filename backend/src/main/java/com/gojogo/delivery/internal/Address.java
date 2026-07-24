package com.gojogo.delivery.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * A delivery address the customer saved. One per user may be the default; the
 * database enforces that with a partial unique index.
 */
@Entity
@Table(name = "address", schema = "delivery")
class Address {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "label", nullable = false)
    private String label;

    @Column(name = "line1", nullable = false)
    private String line1;

    @Column(name = "note", nullable = false)
    private String note = "";

    @Column(name = "latitude")
    private Double latitude;

    @Column(name = "longitude")
    private Double longitude;

    @Column(name = "is_default", nullable = false)
    private boolean isDefault;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    protected Address() {
    }

    Address(UUID userId, String label, String line1, String note,
            Double latitude, Double longitude) {
        this.userId = userId;
        apply(label, line1, note, latitude, longitude);
    }

    void apply(String label, String line1, String note, Double latitude, Double longitude) {
        this.label = label == null || label.isBlank() ? "Home" : label.trim();
        this.line1 = line1.trim();
        this.note = note == null ? "" : note.trim();
        this.latitude = latitude;
        this.longitude = longitude;
    }

    void setDefault(boolean value) {
        this.isDefault = value;
    }

    UUID getId() {
        return id;
    }

    UUID getUserId() {
        return userId;
    }

    String getLabel() {
        return label;
    }

    String getLine1() {
        return line1;
    }

    String getNote() {
        return note;
    }

    Double getLatitude() {
        return latitude;
    }

    Double getLongitude() {
        return longitude;
    }

    boolean isDefault() {
        return isDefault;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }
}
