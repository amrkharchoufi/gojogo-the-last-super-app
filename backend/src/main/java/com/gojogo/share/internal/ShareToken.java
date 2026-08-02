package com.gojogo.share.internal;

import com.gojogo.share.ShareApi;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/** One public link. A pointer, a secret and a deadline — see V33. */
@Entity
@Table(name = "share_token", schema = "share")
class ShareToken {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(nullable = false, length = 64, updatable = false)
    private String token;

    @Column(nullable = false, length = 24, updatable = false)
    private String kind;

    @Column(name = "ref_id", nullable = false, updatable = false)
    private UUID refId;

    @Column(name = "owner_id", nullable = false, updatable = false)
    private UUID ownerId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16, updatable = false)
    private ShareApi.ShareReason reason = ShareApi.ShareReason.SHARE;

    @Column(name = "expires_at", nullable = false)
    private OffsetDateTime expiresAt;

    @Column(name = "revoked_at")
    private OffsetDateTime revokedAt;

    @Column(name = "view_count", nullable = false)
    private int viewCount;

    @Column(name = "last_seen_at")
    private OffsetDateTime lastSeenAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    protected ShareToken() {
    }

    ShareToken(String token, String kind, UUID refId, UUID ownerId,
               ShareApi.ShareReason reason, OffsetDateTime expiresAt) {
        this.token = token;
        this.kind = kind;
        this.refId = refId;
        this.ownerId = ownerId;
        this.reason = reason;
        this.expiresAt = expiresAt;
        this.createdAt = OffsetDateTime.now();
    }

    boolean isLive(OffsetDateTime now) {
        return revokedAt == null && expiresAt.isAfter(now);
    }

    /**
     * Pushes the deadline out, never in.
     *
     * <p>Re-sharing a trip that is running late has to keep the link somebody is
     * already watching alive; shortening one would silently cut them off, and
     * the caller asking for "an hour from now" means "at least", not "exactly".
     */
    void extendTo(OffsetDateTime when) {
        if (when != null && when.isAfter(expiresAt)) this.expiresAt = when;
    }

    void revoke() {
        if (revokedAt == null) this.revokedAt = OffsetDateTime.now();
    }

    /** Somebody opened it. Counted rather than logged, because "did anybody
     *  actually look" is the one question a person who shared a trip asks. */
    void countView() {
        this.viewCount++;
        this.lastSeenAt = OffsetDateTime.now();
    }

    UUID getId() { return id; }
    String getToken() { return token; }
    String getKind() { return kind; }
    UUID getRefId() { return refId; }
    UUID getOwnerId() { return ownerId; }
    ShareApi.ShareReason getReason() { return reason; }
    OffsetDateTime getExpiresAt() { return expiresAt; }
    OffsetDateTime getRevokedAt() { return revokedAt; }
    int getViewCount() { return viewCount; }
}
