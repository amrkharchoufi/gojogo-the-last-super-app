package com.gojogo.social.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;

import java.util.UUID;

/**
 * The sound on a frame — a copy of the catalog track plus the clip window the
 * author chose. Embedded rather than joined: see the V16 migration for why the
 * snapshot is copied instead of referenced.
 */
@Embeddable
class StoryMusic {

    @Column(name = "music_track_id")
    private UUID trackId;

    @Column(name = "music_title")
    private String title;

    @Column(name = "music_artist")
    private String artist;

    @Column(name = "music_artwork_url")
    private String artworkUrl;

    @Column(name = "music_audio_url")
    private String audioUrl;

    @Column(name = "music_start_ms")
    private Integer startMs;

    @Column(name = "music_duration_ms")
    private Integer durationMs;

    protected StoryMusic() {
    }

    StoryMusic(UUID trackId, String title, String artist, String artworkUrl,
               String audioUrl, int startMs, int durationMs) {
        this.trackId = trackId;
        this.title = title;
        this.artist = artist;
        this.artworkUrl = artworkUrl;
        this.audioUrl = audioUrl;
        this.startMs = startMs;
        this.durationMs = durationMs;
    }

    boolean isPresent() {
        return trackId != null;
    }

    UUID getTrackId() {
        return trackId;
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

    Integer getStartMs() {
        return startMs;
    }

    Integer getDurationMs() {
        return durationMs;
    }
}
