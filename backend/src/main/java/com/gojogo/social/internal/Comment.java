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

    @Column(nullable = false)
    private String text;

    @Column(name = "like_count", nullable = false)
    private int likeCount;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected Comment() {
    }

    Comment(UUID postId, UUID authorId, String text) {
        this.postId = postId;
        this.authorId = authorId;
        this.text = text;
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

    int getLikeCount() {
        return likeCount;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }
}
