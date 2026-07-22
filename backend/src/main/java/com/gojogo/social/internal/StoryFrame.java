package com.gojogo.social.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "story_frame", schema = "social")
class StoryFrame {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "author_id", nullable = false)
    private UUID authorId;

    @Column(name = "image_url", nullable = false)
    private String imageUrl;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    @Column(name = "expires_at", nullable = false)
    private OffsetDateTime expiresAt;

    protected StoryFrame() {
    }

    StoryFrame(UUID authorId, String imageUrl) {
        this.authorId = authorId;
        this.imageUrl = imageUrl;
        this.createdAt = OffsetDateTime.now();
        this.expiresAt = this.createdAt.plusHours(24);
    }

    UUID getId() {
        return id;
    }

    UUID getAuthorId() {
        return authorId;
    }

    String getImageUrl() {
        return imageUrl;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }
}
