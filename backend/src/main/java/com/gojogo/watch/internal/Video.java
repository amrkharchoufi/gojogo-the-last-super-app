package com.gojogo.watch.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * One published video. Title, description and thumbnail are authored by the
 * uploader; the three counts are maintained by {@link VideoService} alongside
 * the rows in {@code video_like} / {@code video_comment} / {@code video_view}.
 */
@Entity
@Table(name = "video", schema = "watch")
class Video {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "author_id", nullable = false)
    private UUID authorId;

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false)
    private VideoKind kind;

    @Column(name = "title", nullable = false)
    private String title;

    @Column(name = "description", nullable = false)
    private String description = "";

    @Column(name = "thumb_url")
    private String thumbUrl;

    @Column(name = "video_url", nullable = false)
    private String videoUrl;

    @Column(name = "duration_seconds", nullable = false)
    private int durationSeconds;

    @Column(name = "like_count", nullable = false)
    private int likeCount;

    @Column(name = "comment_count", nullable = false)
    private int commentCount;

    @Column(name = "view_count", nullable = false)
    private int viewCount;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    /** When a moderator hid this after a report (V28). Its author still sees it,
     *  flagged; nobody else does. Distinct from delete, which is not undoable. */
    @Column(name = "hidden_at")
    private OffsetDateTime hiddenAt;

    protected Video() {
    }

    Video(UUID authorId, VideoKind kind, String title, String description,
          String thumbUrl, String videoUrl, int durationSeconds) {
        this.authorId = authorId;
        this.kind = kind;
        this.title = title;
        this.description = description == null ? "" : description;
        this.thumbUrl = thumbUrl;
        this.videoUrl = videoUrl;
        this.durationSeconds = Math.max(0, durationSeconds);
        this.createdAt = OffsetDateTime.now();
    }

    /** Applies an edit. A null field means "leave as it is", not "clear it". */
    void edit(String newTitle, String newDescription, String newThumbUrl) {
        if (newTitle != null && !newTitle.isBlank()) {
            this.title = newTitle;
        }
        if (newDescription != null) {
            this.description = newDescription;
        }
        if (newThumbUrl != null && !newThumbUrl.isBlank()) {
            this.thumbUrl = newThumbUrl;
        }
    }

    UUID getId() {
        return id;
    }

    UUID getAuthorId() {
        return authorId;
    }

    VideoKind getKind() {
        return kind;
    }

    String getTitle() {
        return title;
    }

    String getDescription() {
        return description;
    }

    String getThumbUrl() {
        return thumbUrl;
    }

    String getVideoUrl() {
        return videoUrl;
    }

    int getDurationSeconds() {
        return durationSeconds;
    }

    int getLikeCount() {
        return likeCount;
    }

    int getCommentCount() {
        return commentCount;
    }

    int getViewCount() {
        return viewCount;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    boolean isHidden() {
        return hiddenAt != null;
    }

    void setHidden(boolean hidden) {
        this.hiddenAt = hidden ? OffsetDateTime.now() : null;
    }
}
