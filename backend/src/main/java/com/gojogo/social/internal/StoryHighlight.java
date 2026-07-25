package com.gojogo.social.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/** A titled, permanent collection of story frames, shown on the owner's profile. */
@Entity
@Table(name = "story_highlight", schema = "social")
class StoryHighlight {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "owner_id", nullable = false)
    private UUID ownerId;

    @Column(name = "title", nullable = false)
    private String title;

    @Column(name = "cover_url")
    private String coverUrl;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    @Column(name = "updated_at")
    private OffsetDateTime updatedAt;

    protected StoryHighlight() {
    }

    StoryHighlight(UUID ownerId, String title, String coverUrl) {
        this.ownerId = ownerId;
        this.title = title;
        this.coverUrl = coverUrl;
        this.createdAt = OffsetDateTime.now();
    }

    UUID getId() {
        return id;
    }

    UUID getOwnerId() {
        return ownerId;
    }

    String getTitle() {
        return title;
    }

    String getCoverUrl() {
        return coverUrl;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    void rename(String title, String coverUrl) {
        this.title = title;
        this.coverUrl = coverUrl;
        this.updatedAt = OffsetDateTime.now();
    }
}
