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
 * A viewer's quick-emoji reaction to one frame. One per person per frame —
 * reacting again replaces the emoji, which is why {@code emoji} is mutable and
 * the upsert path goes through {@link #changeTo}.
 */
@Entity
@Table(name = "story_reaction", schema = "social")
@IdClass(StoryReaction.Key.class)
class StoryReaction {

    @Id
    @Column(name = "frame_id")
    private UUID frameId;

    @Id
    @Column(name = "viewer_id")
    private UUID viewerId;

    @Column(name = "emoji", nullable = false)
    private String emoji;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected StoryReaction() {
    }

    StoryReaction(UUID frameId, UUID viewerId, String emoji) {
        this.frameId = frameId;
        this.viewerId = viewerId;
        this.emoji = emoji;
        this.createdAt = OffsetDateTime.now();
    }

    UUID getFrameId() {
        return frameId;
    }

    UUID getViewerId() {
        return viewerId;
    }

    String getEmoji() {
        return emoji;
    }

    void changeTo(String emoji) {
        this.emoji = emoji;
        this.createdAt = OffsetDateTime.now();
    }

    record Key(UUID frameId, UUID viewerId) implements Serializable {
    }
}
