-- Milestone: platform notifications (activity feed). First consumer of the
-- social domain events (UserFollowed / PostLiked / PostCommented). Own schema;
-- actor/recipient/post/comment columns are plain UUIDs — no cross-schema FKs.

CREATE SCHEMA IF NOT EXISTS notifications;

CREATE TABLE notifications.notification (
    id           UUID        PRIMARY KEY,
    recipient_id UUID        NOT NULL,
    type         VARCHAR(20) NOT NULL,
    actor_id     UUID        NOT NULL,
    post_id      UUID,
    comment_id   UUID,
    created_at   TIMESTAMPTZ NOT NULL,
    is_read      BOOLEAN     NOT NULL DEFAULT FALSE
);

-- Feed query: a recipient's notifications, newest first (keyset on created_at).
CREATE INDEX notification_recipient_created_idx
    ON notifications.notification (recipient_id, created_at DESC);
