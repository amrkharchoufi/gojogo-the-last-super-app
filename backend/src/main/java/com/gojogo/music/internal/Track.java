package com.gojogo.music.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/** One catalog track. Rows are created by the operator, not by the app. */
@Entity
@Table(name = "track", schema = "music")
class Track {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "title", nullable = false)
    private String title;

    @Column(name = "artist", nullable = false)
    private String artist;

    @Column(name = "artwork_url")
    private String artworkUrl;

    @Column(name = "audio_url", nullable = false)
    private String audioUrl;

    @Column(name = "duration_ms", nullable = false)
    private int durationMs;

    @Column(name = "is_active", nullable = false)
    private boolean active;

    @Column(name = "trending_rank")
    private Integer trendingRank;

    @Column(name = "use_count", nullable = false)
    private int useCount;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected Track() {
    }

    UUID getId() {
        return id;
    }

    String getTitle() {
        return title;
    }

    String getArtist() {
        return artist;
    }

    String getArtworkUrl() {
        return artworkUrl;
    }

    String getAudioUrl() {
        return audioUrl;
    }

    int getDurationMs() {
        return durationMs;
    }

    boolean isActive() {
        return active;
    }

    int getUseCount() {
        return useCount;
    }
}
