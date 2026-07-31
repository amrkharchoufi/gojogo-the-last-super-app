package com.gojogo.social.internal;

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
 * One person tagged in one caption or comment. {@code handle} is the handle
 * <em>as written</em>, which is what the client matches against the body text to
 * find the span to underline — it is history and must never be rewritten when
 * that person renames. {@code profileId} is the link, and it survives renames.
 */
@Entity
@Table(name = "mention", schema = "social")
class Mention {

    @Id
    @GeneratedValue
    private UUID id;

    @Enumerated(EnumType.STRING)
    @Column(name = "target_kind", nullable = false, length = 16)
    private MentionTarget targetKind;

    @Column(name = "target_id", nullable = false)
    private UUID targetId;

    @Column(name = "profile_id", nullable = false)
    private UUID profileId;

    @Column(nullable = false, length = 60)
    private String handle;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected Mention() {
    }

    Mention(MentionTarget targetKind, UUID targetId, UUID profileId, String handle) {
        this.targetKind = targetKind;
        this.targetId = targetId;
        this.profileId = profileId;
        this.handle = handle;
        this.createdAt = OffsetDateTime.now();
    }

    UUID getTargetId() {
        return targetId;
    }

    UUID getProfileId() {
        return profileId;
    }

    String getHandle() {
        return handle;
    }
}
