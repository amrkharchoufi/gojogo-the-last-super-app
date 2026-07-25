package com.gojogo.social.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Embedded;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * One frame of a story: a photo, a video, or a text card, live for 24 hours.
 *
 * <p>Deletion is soft. A frame outlives its expiry when it is pinned to a
 * highlight, and {@code story_view} cascades on a hard delete — which would
 * silently drop the seen-state and the viewers list with it.
 */
@Entity
@Table(name = "story_frame", schema = "social")
class StoryFrame {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "author_id", nullable = false)
    private UUID authorId;

    @Enumerated(EnumType.STRING)
    @Column(name = "media_type", nullable = false)
    private StoryMediaType mediaType;

    /** The photo, or a video's poster frame. Null on a text card. */
    @Column(name = "image_url")
    private String imageUrl;

    @Column(name = "video_url")
    private String videoUrl;

    /** Measured video length; null on stills, where the client uses its own default. */
    @Column(name = "duration_ms")
    private Integer durationMs;

    @Column(name = "caption")
    private String caption;

    /** Opaque to the server — see the column comment in V11. */
    @Column(name = "overlays_json")
    private String overlaysJson;

    /** Background token for a text card (a palette key, not a color value). */
    @Column(name = "background")
    private String background;

    @Enumerated(EnumType.STRING)
    @Column(name = "audience", nullable = false)
    private StoryAudience audience;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    @Column(name = "expires_at", nullable = false)
    private OffsetDateTime expiresAt;

    @Column(name = "deleted_at")
    private OffsetDateTime deletedAt;

    /** The sound on this frame, if any — a snapshot, not a join. See V16. */
    @Embedded
    private StoryMusic music;

    protected StoryFrame() {
    }

    StoryFrame(UUID authorId, StoryMediaType mediaType, String imageUrl, String videoUrl,
               Integer durationMs, String caption, String overlaysJson, String background,
               StoryAudience audience) {
        this.authorId = authorId;
        this.mediaType = mediaType;
        this.imageUrl = imageUrl;
        this.videoUrl = videoUrl;
        this.durationMs = durationMs;
        this.caption = caption;
        this.overlaysJson = overlaysJson;
        this.background = background;
        this.audience = audience;
        this.createdAt = OffsetDateTime.now();
        this.expiresAt = this.createdAt.plusHours(24);
    }

    UUID getId() {
        return id;
    }

    UUID getAuthorId() {
        return authorId;
    }

    StoryMediaType getMediaType() {
        return mediaType;
    }

    String getImageUrl() {
        return imageUrl;
    }

    String getVideoUrl() {
        return videoUrl;
    }

    Integer getDurationMs() {
        return durationMs;
    }

    String getCaption() {
        return caption;
    }

    String getOverlaysJson() {
        return overlaysJson;
    }

    String getBackground() {
        return background;
    }

    StoryAudience getAudience() {
        return audience;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    OffsetDateTime getExpiresAt() {
        return expiresAt;
    }

    OffsetDateTime getDeletedAt() {
        return deletedAt;
    }

    /** Null when the frame is silent — never a half-populated snapshot (V16 CHECK). */
    StoryMusic getMusic() {
        return music != null && music.isPresent() ? music : null;
    }

    void attach(StoryMusic music) {
        this.music = music;
    }

    void softDelete() {
        this.deletedAt = OffsetDateTime.now();
    }

    /** Every URL this frame references, for {@code MediaApi.markReferenced}. */
    java.util.List<String> mediaUrls() {
        java.util.List<String> urls = new java.util.ArrayList<>(2);
        if (imageUrl != null) {
            urls.add(imageUrl);
        }
        if (videoUrl != null) {
            urls.add(videoUrl);
        }
        return urls;
    }
}
