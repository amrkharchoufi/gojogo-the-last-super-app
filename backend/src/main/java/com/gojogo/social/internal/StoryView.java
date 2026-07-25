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
 * One person having seen one frame, with the time they first did — the viewers
 * list is ordered by it, so re-marking a seen frame must not overwrite it.
 * {@link StoryService#markSeen} guards with {@code existsById} for that reason:
 * an assigned-id entity is merged, not inserted, so a second save would be a
 * silent UPDATE rather than the duplicate-key it looks like.
 */
@Entity
@Table(name = "story_view", schema = "social")
@IdClass(StoryView.Key.class)
class StoryView {

    @Id
    @Column(name = "frame_id")
    private UUID frameId;

    @Id
    @Column(name = "viewer_id")
    private UUID viewerId;

    @Column(name = "viewed_at", nullable = false)
    private OffsetDateTime viewedAt;

    protected StoryView() {
    }

    StoryView(UUID frameId, UUID viewerId) {
        this.frameId = frameId;
        this.viewerId = viewerId;
        this.viewedAt = OffsetDateTime.now();
    }

    UUID getFrameId() {
        return frameId;
    }

    UUID getViewerId() {
        return viewerId;
    }

    OffsetDateTime getViewedAt() {
        return viewedAt;
    }

    record Key(UUID frameId, UUID viewerId) implements Serializable {
    }
}
