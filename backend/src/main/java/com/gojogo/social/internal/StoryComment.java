package com.gojogo.social.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * A text reply to a story frame. Stored like a comment; read back private to
 * the frame's author (a viewer only ever sees their own replies).
 */
@Entity
@Table(name = "story_comment", schema = "social")
class StoryComment {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "frame_id", nullable = false)
    private UUID frameId;

    @Column(name = "author_id", nullable = false)
    private UUID authorId;

    @Column(name = "text", nullable = false)
    private String text;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected StoryComment() {
    }

    StoryComment(UUID frameId, UUID authorId, String text) {
        this.frameId = frameId;
        this.authorId = authorId;
        this.text = text;
        this.createdAt = OffsetDateTime.now();
    }

    UUID getId() {
        return id;
    }

    UUID getFrameId() {
        return frameId;
    }

    UUID getAuthorId() {
        return authorId;
    }

    String getText() {
        return text;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }
}
