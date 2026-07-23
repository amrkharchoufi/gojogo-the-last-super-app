package com.gojogo.notifications.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * One activity-feed row for a recipient. Id + createdAt are app-assigned (same
 * approach the entity uses everywhere); {@code type} is a small enum-like string
 * (follow / like / comment).
 */
@Entity
@Table(name = "notification", schema = "notifications")
class Notification {

    @Id
    private UUID id;

    @Column(name = "recipient_id", nullable = false)
    private UUID recipientId;

    @Column(name = "type", nullable = false)
    private String type;

    @Column(name = "actor_id", nullable = false)
    private UUID actorId;

    @Column(name = "post_id")
    private UUID postId;

    @Column(name = "comment_id")
    private UUID commentId;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    @Column(name = "is_read", nullable = false)
    private boolean read;

    protected Notification() {
    }

    Notification(UUID recipientId, String type, UUID actorId, UUID postId, UUID commentId,
                 OffsetDateTime createdAt) {
        this.id = UUID.randomUUID();
        this.recipientId = recipientId;
        this.type = type;
        this.actorId = actorId;
        this.postId = postId;
        this.commentId = commentId;
        this.createdAt = createdAt;
        this.read = false;
    }

    UUID getId() { return id; }
    UUID getRecipientId() { return recipientId; }
    String getType() { return type; }
    UUID getActorId() { return actorId; }
    UUID getPostId() { return postId; }
    UUID getCommentId() { return commentId; }
    OffsetDateTime getCreatedAt() { return createdAt; }
    boolean isRead() { return read; }
}
