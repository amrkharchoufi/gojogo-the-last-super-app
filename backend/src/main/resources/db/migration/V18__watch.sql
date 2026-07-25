-- Watch — user video (long-form + shorts). A vertical product surface
-- (ARCHITECTURE.md §2), so it owns its own schema; it does NOT live in
-- `social`, and it never reads social's tables.
--
-- Scope note: this is the *catalog and engagement* half of Watch. The transcode
-- pipeline (S3 → MediaConvert → HLS) is still Phase 3 — `video_url` here is the
-- same presigned-S3 object a post's video already uses, played directly.
--
-- Reminder: author_id / user_id columns referencing profile.user_profile are
-- plain UUIDs on purpose — no foreign keys across schemas, ever.

CREATE SCHEMA IF NOT EXISTS watch;

CREATE TABLE watch.video (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id        UUID        NOT NULL,
    -- LONG_FORM feeds the Watch tab, SHORT the vertical Shorts feed. One table:
    -- they differ in presentation and aspect, not in anything the server does.
    kind             VARCHAR(16) NOT NULL,
    -- A short's caption rides in `title`; long-form additionally has a body.
    title            TEXT        NOT NULL,
    description      TEXT        NOT NULL DEFAULT '',
    thumb_url        TEXT,
    video_url        TEXT        NOT NULL,
    -- Whole seconds. The client renders "1:00" from it rather than storing a
    -- formatted string, which was one of the fake fields this replaces.
    duration_seconds INT         NOT NULL DEFAULT 0,
    like_count       INT         NOT NULL DEFAULT 0,
    comment_count    INT         NOT NULL DEFAULT 0,
    -- Denormalised count of watch.video_view; kept in step by VideoService.
    view_count       INT         NOT NULL DEFAULT 0,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE watch.video
    ADD CONSTRAINT video_kind_chk CHECK (kind IN ('LONG_FORM', 'SHORT')),
    ADD CONSTRAINT video_duration_chk CHECK (duration_seconds >= 0);

CREATE INDEX video_kind_created_idx   ON watch.video (kind, created_at DESC);
CREATE INDEX video_author_created_idx ON watch.video (author_id, created_at DESC);

CREATE TABLE watch.video_like (
    video_id   UUID        NOT NULL REFERENCES watch.video (id) ON DELETE CASCADE,
    user_id    UUID        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (video_id, user_id)
);

CREATE TABLE watch.video_save (
    video_id   UUID        NOT NULL REFERENCES watch.video (id) ON DELETE CASCADE,
    user_id    UUID        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (video_id, user_id)
);

-- One row per (video, viewer), so `view_count` is *distinct viewers* rather
-- than playbacks. That makes the endpoint idempotent — a client that replays or
-- retries can't inflate the number — and it's the figure every video product
-- actually shows next to a title.
CREATE TABLE watch.video_view (
    video_id  UUID        NOT NULL REFERENCES watch.video (id) ON DELETE CASCADE,
    viewer_id UUID        NOT NULL,
    viewed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (video_id, viewer_id)
);

CREATE TABLE watch.video_comment (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id   UUID        NOT NULL REFERENCES watch.video (id) ON DELETE CASCADE,
    author_id  UUID        NOT NULL,
    text       TEXT        NOT NULL,
    like_count INT         NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX video_comment_video_idx ON watch.video_comment (video_id, created_at);

CREATE TABLE watch.video_comment_like (
    comment_id UUID        NOT NULL REFERENCES watch.video_comment (id) ON DELETE CASCADE,
    user_id    UUID        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (comment_id, user_id)
);
