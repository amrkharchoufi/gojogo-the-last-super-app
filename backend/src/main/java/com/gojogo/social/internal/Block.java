package com.gojogo.social.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

import java.io.Serializable;
import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * One person deciding not to be in the same room as another.
 *
 * <p>The row is one-directional because the <em>act</em> is: only the blocker
 * has one. Every read of it is bidirectional, because the <em>effect</em> is —
 * see {@link BlockService}.
 */
@Entity
@Table(name = "block", schema = "social")
@IdClass(Block.Key.class)
class Block {

    @Id
    @Column(name = "blocker_id")
    private UUID blockerId;

    @Id
    @Column(name = "blocked_id")
    private UUID blockedId;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected Block() {
    }

    Block(UUID blockerId, UUID blockedId) {
        this.blockerId = blockerId;
        this.blockedId = blockedId;
        this.createdAt = OffsetDateTime.now();
    }

    UUID getBlockerId() {
        return blockerId;
    }

    UUID getBlockedId() {
        return blockedId;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    record Key(UUID blockerId, UUID blockedId) implements Serializable {
    }
}
