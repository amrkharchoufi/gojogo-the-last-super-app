package com.gojogo.social.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

import java.io.Serializable;
import java.util.UUID;

@Entity
@Table(name = "comment_like", schema = "social")
@IdClass(CommentLike.Key.class)
class CommentLike {

    @Id
    @Column(name = "comment_id")
    private UUID commentId;

    @Id
    @Column(name = "user_id")
    private UUID userId;

    protected CommentLike() {
    }

    CommentLike(UUID commentId, UUID userId) {
        this.commentId = commentId;
        this.userId = userId;
    }

    record Key(UUID commentId, UUID userId) implements Serializable {
    }
}
