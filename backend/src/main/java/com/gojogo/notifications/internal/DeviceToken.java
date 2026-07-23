package com.gojogo.notifications.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/** An APNs device token registered by a signed-in device. */
@Entity
@Table(name = "device_token", schema = "notifications")
class DeviceToken {

    @Id
    private UUID id;

    @Column(name = "profile_id", nullable = false)
    private UUID profileId;

    @Column(name = "token", nullable = false, unique = true)
    private String token;

    @Column(name = "platform", nullable = false)
    private String platform;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    protected DeviceToken() {
    }

    DeviceToken(UUID profileId, String token, String platform) {
        this.id = UUID.randomUUID();
        this.profileId = profileId;
        this.token = token;
        this.platform = platform;
        this.updatedAt = OffsetDateTime.now();
    }

    void reassign(UUID profileId) {
        this.profileId = profileId;
        this.updatedAt = OffsetDateTime.now();
    }

    UUID getProfileId() { return profileId; }
    String getToken() { return token; }
    String getPlatform() { return platform; }
}
