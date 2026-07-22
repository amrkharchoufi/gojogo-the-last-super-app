package com.gojogo.social.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

import java.io.Serializable;
import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "follow", schema = "social")
@IdClass(Follow.Key.class)
class Follow {

    @Id
    @Column(name = "follower_id")
    private UUID followerId;

    @Id
    @Column(name = "followee_id")
    private UUID followeeId;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected Follow() {
    }

    Follow(UUID followerId, UUID followeeId) {
        this.followerId = followerId;
        this.followeeId = followeeId;
        this.createdAt = OffsetDateTime.now();
    }

    record Key(UUID followerId, UUID followeeId) implements Serializable {
    }
}
