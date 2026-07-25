package com.gojogo.watch.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

import java.io.Serializable;
import java.time.OffsetDateTime;
import java.util.UUID;

// The join rows behind a video's three counts, plus comments. Each is its own
// table so a count can be rebuilt from truth if it ever drifts.
//
// Like / save / view are all keyed by (video, user), which is what makes them
// idempotent: a retry writes the same row twice and the duplicate-key path
// leaves the count alone.

@Entity
@Table(name = "video_like", schema = "watch")
@IdClass(VideoLike.Key.class)
class VideoLike {

    @Id
    @Column(name = "video_id")
    private UUID videoId;

    @Id
    @Column(name = "user_id")
    private UUID userId;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected VideoLike() {
    }

    VideoLike(UUID videoId, UUID userId) {
        this.videoId = videoId;
        this.userId = userId;
        this.createdAt = OffsetDateTime.now();
    }

    record Key(UUID videoId, UUID userId) implements Serializable {
    }
}

@Entity
@Table(name = "video_save", schema = "watch")
@IdClass(VideoSave.Key.class)
class VideoSave {

    @Id
    @Column(name = "video_id")
    private UUID videoId;

    @Id
    @Column(name = "user_id")
    private UUID userId;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected VideoSave() {
    }

    VideoSave(UUID videoId, UUID userId) {
        this.videoId = videoId;
        this.userId = userId;
        this.createdAt = OffsetDateTime.now();
    }

    record Key(UUID videoId, UUID userId) implements Serializable {
    }
}

/**
 * One row per (video, viewer) — so the count on a video is distinct viewers,
 * not playbacks, and re-watching never inflates it.
 */
@Entity
@Table(name = "video_view", schema = "watch")
@IdClass(VideoView.Key.class)
class VideoView {

    @Id
    @Column(name = "video_id")
    private UUID videoId;

    @Id
    @Column(name = "viewer_id")
    private UUID viewerId;

    @Column(name = "viewed_at", nullable = false)
    private OffsetDateTime viewedAt;

    protected VideoView() {
    }

    VideoView(UUID videoId, UUID viewerId) {
        this.videoId = videoId;
        this.viewerId = viewerId;
        this.viewedAt = OffsetDateTime.now();
    }

    record Key(UUID videoId, UUID viewerId) implements Serializable {
    }
}

@Entity
@Table(name = "video_comment", schema = "watch")
class VideoComment {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "video_id", nullable = false)
    private UUID videoId;

    @Column(name = "author_id", nullable = false)
    private UUID authorId;

    @Column(name = "text", nullable = false)
    private String text;

    @Column(name = "like_count", nullable = false)
    private int likeCount;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected VideoComment() {
    }

    VideoComment(UUID videoId, UUID authorId, String text) {
        this.videoId = videoId;
        this.authorId = authorId;
        this.text = text;
        this.createdAt = OffsetDateTime.now();
    }

    UUID getId() {
        return id;
    }

    UUID getVideoId() {
        return videoId;
    }

    UUID getAuthorId() {
        return authorId;
    }

    String getText() {
        return text;
    }

    int getLikeCount() {
        return likeCount;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }
}

@Entity
@Table(name = "video_comment_like", schema = "watch")
@IdClass(VideoCommentLike.Key.class)
class VideoCommentLike {

    @Id
    @Column(name = "comment_id")
    private UUID commentId;

    @Id
    @Column(name = "user_id")
    private UUID userId;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    protected VideoCommentLike() {
    }

    VideoCommentLike(UUID commentId, UUID userId) {
        this.commentId = commentId;
        this.userId = userId;
        this.createdAt = OffsetDateTime.now();
    }

    record Key(UUID commentId, UUID userId) implements Serializable {
    }
}
