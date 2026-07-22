package com.gojogo.social.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

import java.io.Serializable;
import java.util.UUID;

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

    protected StoryView() {
    }

    StoryView(UUID frameId, UUID viewerId) {
        this.frameId = frameId;
        this.viewerId = viewerId;
    }

    record Key(UUID frameId, UUID viewerId) implements Serializable {
    }
}
