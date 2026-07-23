package com.gojogo.notifications.internal;

import com.gojogo.social.PostCommented;
import com.gojogo.social.PostLiked;
import com.gojogo.social.UserFollowed;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.event.TransactionalEventListener;

import java.time.OffsetDateTime;

/**
 * Consumes the social module's domain events and persists activity rows. Each
 * handler runs AFTER the social transaction commits (so no notification for a
 * rolled-back action) in its own new transaction. In-process for now; the same
 * events could later feed SQS/EventBridge without touching the publishers.
 */
@Component
class NotificationListeners {

    private final NotificationService notifications;

    NotificationListeners(NotificationService notifications) {
        this.notifications = notifications;
    }

    @TransactionalEventListener
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    void onFollow(UserFollowed event) {
        notifications.record(event.followeeId(), "follow", event.followerId(),
            null, null, OffsetDateTime.now());
    }

    @TransactionalEventListener
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    void onLike(PostLiked event) {
        notifications.record(event.postAuthorId(), "like", event.likerId(),
            event.postId(), null, event.at());
    }

    @TransactionalEventListener
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    void onComment(PostCommented event) {
        notifications.record(event.postAuthorId(), "comment", event.commenterId(),
            event.postId(), event.commentId(), event.at());
    }
}
