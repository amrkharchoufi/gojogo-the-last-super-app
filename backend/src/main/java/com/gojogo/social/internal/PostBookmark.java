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
@Table(name = "post_bookmark", schema = "social")
@IdClass(PostBookmark.Key.class)
class PostBookmark {

    @Id
    @Column(name = "post_id")
    private UUID postId;

    @Id
    @Column(name = "user_id")
    private UUID userId;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected PostBookmark() {
    }

    PostBookmark(UUID postId, UUID userId) {
        this.postId = postId;
        this.userId = userId;
        this.createdAt = OffsetDateTime.now();
    }

    record Key(UUID postId, UUID userId) implements Serializable {
    }
}
