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
 * One entry on {@code owner}'s close-friends list. One-directional by design —
 * being on someone's list says nothing about whether they are on yours.
 */
@Entity
@Table(name = "close_friend", schema = "social")
@IdClass(CloseFriend.Key.class)
class CloseFriend {

    @Id
    @Column(name = "owner_id")
    private UUID ownerId;

    @Id
    @Column(name = "friend_id")
    private UUID friendId;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected CloseFriend() {
    }

    CloseFriend(UUID ownerId, UUID friendId) {
        this.ownerId = ownerId;
        this.friendId = friendId;
        this.createdAt = OffsetDateTime.now();
    }

    UUID getFriendId() {
        return friendId;
    }

    record Key(UUID ownerId, UUID friendId) implements Serializable {
    }
}
