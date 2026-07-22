package com.gojogo.social.internal;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Entity
@Table(name = "post", schema = "social")
class Post {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "author_id", nullable = false)
    private UUID authorId;

    @Column(name = "text")
    private String text;

    @Column(name = "image_aspect", nullable = false)
    private float imageAspect = 1.0f;

    @Column(name = "like_count", nullable = false)
    private int likeCount;

    @Column(name = "comment_count", nullable = false)
    private int commentCount;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    @OneToMany(mappedBy = "post", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.LAZY)
    @OrderBy("sortOrder")
    private List<PostMedia> media = new ArrayList<>();

    protected Post() {
    }

    Post(UUID authorId, String text, float imageAspect) {
        this.authorId = authorId;
        this.text = text;
        this.imageAspect = imageAspect;
        this.createdAt = OffsetDateTime.now();
    }

    void addMedia(String imageUrl, String videoUrl) {
        media.add(new PostMedia(this, media.size(), imageUrl, videoUrl));
    }

    UUID getId() {
        return id;
    }

    UUID getAuthorId() {
        return authorId;
    }

    String getText() {
        return text;
    }

    float getImageAspect() {
        return imageAspect;
    }

    int getLikeCount() {
        return likeCount;
    }

    int getCommentCount() {
        return commentCount;
    }

    OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    List<PostMedia> getMedia() {
        return media;
    }
}
