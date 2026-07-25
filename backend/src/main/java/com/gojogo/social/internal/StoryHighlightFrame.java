package com.gojogo.social.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

import java.io.Serializable;
import java.util.UUID;

/** A frame's place in a highlight. */
@Entity
@Table(name = "story_highlight_frame", schema = "social")
@IdClass(StoryHighlightFrame.Key.class)
class StoryHighlightFrame {

    @Id
    @Column(name = "highlight_id")
    private UUID highlightId;

    @Id
    @Column(name = "frame_id")
    private UUID frameId;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    protected StoryHighlightFrame() {
    }

    StoryHighlightFrame(UUID highlightId, UUID frameId, int sortOrder) {
        this.highlightId = highlightId;
        this.frameId = frameId;
        this.sortOrder = sortOrder;
    }

    UUID getHighlightId() {
        return highlightId;
    }

    UUID getFrameId() {
        return frameId;
    }

    int getSortOrder() {
        return sortOrder;
    }

    record Key(UUID highlightId, UUID frameId) implements Serializable {
    }
}
