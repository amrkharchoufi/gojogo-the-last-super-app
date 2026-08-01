package com.gojogo.social.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "comment", schema = "social")
class Comment {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "post_id", nullable = false)
    private UUID postId;

    @Column(name = "author_id", nullable = false)
    private UUID authorId;

    /**
     * The top-level comment this answers, or null if this <em>is</em> one.
     * Never points at another reply: threads are one level deep and the service
     * re-points a reply-to-a-reply at their shared parent.
     */
    @Column(name = "parent_id")
    private UUID parentId;

    @Column(nullable = false)
    private String text;

    @Column(name = "like_count", nullable = false)
    private int likeCount;

    @Column(name = "reply_count", nullable = false)
    private int replyCount;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    /** When a moderator hid this after a report (V28) — see {@link Post}. */
    @Column(name = "hidden_at")
    private OffsetDateTime hiddenAt;

    protected Comment() {
    }

    Comment(UUID postId, UUID authorId, String text, UUID parentId) {
        this.postId = postId;
        this.authorId = authorId;
        this.text = text;
        this.parentId = parentId;
        this.createdAt = OffsetDateTime.now();
    }

    UUID getId() {
        return id;
    }

    UUID getPostId() {
        return postId;
    }

    UUID getAuthorId() {
        return authorId;
    }

    String getText() {
        return text;
    }

    UUID getParentId() {
        return parentId;
    }

    int getLikeCount() {
        return likeCount;
    }

    int getReplyCount() {
        return replyCount;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    boolean isHidden() {
        return hiddenAt != null;
    }

    void setHidden(boolean hidden) {
        this.hiddenAt = hidden ? OffsetDateTime.now() : null;
    }
}
