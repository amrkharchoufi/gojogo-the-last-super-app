package com.gojogo.social.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

import java.io.Serializable;
import java.time.OffsetDateTime;
import java.util.UUID;

/** "Hide {@code muted}'s stories from me" — independent of following them. */
@Entity
@Table(name = "story_mute", schema = "social")
@IdClass(StoryMute.Key.class)
class StoryMute {

    @Id
    @Column(name = "muter_id")
    private UUID muterId;

    @Id
    @Column(name = "muted_id")
    private UUID mutedId;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected StoryMute() {
    }

    StoryMute(UUID muterId, UUID mutedId) {
        this.muterId = muterId;
        this.mutedId = mutedId;
        this.createdAt = OffsetDateTime.now();
    }

    record Key(UUID muterId, UUID mutedId) implements Serializable {
    }
}
