package com.gojogo.social.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

import java.util.UUID;

@Entity
@Table(name = "post_media", schema = "social")
class PostMedia {

    @Id
    @GeneratedValue
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "post_id", nullable = false)
    private Post post;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    @Column(name = "image_url")
    private String imageUrl;

    @Column(name = "video_url")
    private String videoUrl;

    protected PostMedia() {
    }

    PostMedia(Post post, int sortOrder, String imageUrl, String videoUrl) {
        this.post = post;
        this.sortOrder = sortOrder;
        this.imageUrl = imageUrl;
        this.videoUrl = videoUrl;
    }

    UUID getId() {
        return id;
    }

    String getImageUrl() {
        return imageUrl;
    }

    String getVideoUrl() {
        return videoUrl;
    }
}
