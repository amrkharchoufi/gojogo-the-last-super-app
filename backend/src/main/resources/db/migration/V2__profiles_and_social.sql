-- Milestone 2: profile fields + social graph/content tables.
-- Reminder: author_id / user_id columns referencing profile.user_profile are
-- plain UUIDs on purpose — no foreign keys across schemas, ever (ARCHITECTURE.md §3).

-- ── profile ────────────────────────────────────────────────────────────────
ALTER TABLE profile.user_profile
    ADD COLUMN handle     VARCHAR(60),
    ADD COLUMN bio        TEXT        NOT NULL DEFAULT '',
    ADD COLUMN category   VARCHAR(60) NOT NULL DEFAULT 'Creator',
    ADD COLUMN birth_year INT,
    ADD COLUMN avatar_url TEXT;

UPDATE profile.user_profile
SET handle = 'user_' || substr(replace(id::text, '-', ''), 1, 10)
WHERE handle IS NULL;

ALTER TABLE profile.user_profile
    ALTER COLUMN handle SET NOT NULL,
    ADD CONSTRAINT user_profile_handle_key UNIQUE (handle);

CREATE TABLE profile.user_interest (
    profile_id UUID        NOT NULL REFERENCES profile.user_profile (id) ON DELETE CASCADE,
    interest   VARCHAR(60) NOT NULL,
    PRIMARY KEY (profile_id, interest)
);

-- ── social ─────────────────────────────────────────────────────────────────
CREATE TABLE social.post (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id     UUID        NOT NULL,
    text          TEXT,
    image_aspect  REAL        NOT NULL DEFAULT 1.0,
    like_count    INT         NOT NULL DEFAULT 0,
    comment_count INT         NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX post_author_created_idx ON social.post (author_id, created_at DESC);
CREATE INDEX post_created_idx ON social.post (created_at DESC);

CREATE TABLE social.post_media (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id    UUID NOT NULL REFERENCES social.post (id) ON DELETE CASCADE,
    sort_order INT  NOT NULL,
    image_url  TEXT,
    video_url  TEXT
);
CREATE INDEX post_media_post_idx ON social.post_media (post_id);

CREATE TABLE social.post_like (
    post_id    UUID        NOT NULL REFERENCES social.post (id) ON DELETE CASCADE,
    user_id    UUID        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, user_id)
);

CREATE TABLE social.post_bookmark (
    post_id    UUID        NOT NULL REFERENCES social.post (id) ON DELETE CASCADE,
    user_id    UUID        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, user_id)
);

CREATE TABLE social.comment (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id    UUID        NOT NULL REFERENCES social.post (id) ON DELETE CASCADE,
    author_id  UUID        NOT NULL,
    text       TEXT        NOT NULL,
    like_count INT         NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX comment_post_created_idx ON social.comment (post_id, created_at);

CREATE TABLE social.comment_like (
    comment_id UUID NOT NULL REFERENCES social.comment (id) ON DELETE CASCADE,
    user_id    UUID NOT NULL,
    PRIMARY KEY (comment_id, user_id)
);

CREATE TABLE social.follow (
    follower_id UUID        NOT NULL,
    followee_id UUID        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (follower_id, followee_id)
);
CREATE INDEX follow_followee_idx ON social.follow (followee_id);

CREATE TABLE social.story_frame (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id  UUID        NOT NULL,
    image_url  TEXT        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '24 hours'
);
CREATE INDEX story_frame_author_idx ON social.story_frame (author_id, expires_at);

CREATE TABLE social.story_view (
    frame_id  UUID NOT NULL REFERENCES social.story_frame (id) ON DELETE CASCADE,
    viewer_id UUID NOT NULL,
    PRIMARY KEY (frame_id, viewer_id)
);
