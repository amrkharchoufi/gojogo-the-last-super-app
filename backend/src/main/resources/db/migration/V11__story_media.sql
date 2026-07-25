-- Stories · Slice 1: a frame stops being "one image URL".
--
-- A story frame is now one of three things — a photo, a video, or a text card
-- with no media at all — carrying an optional caption and a client-authored
-- overlay spec (text/sticker placements). It also gains a soft delete, because
-- highlights (V13) keep a frame alive past its 24h expiry and `story_view` has
-- an ON DELETE CASCADE that would take the seen-state with a hard delete.

ALTER TABLE social.story_frame
    ADD COLUMN media_type    VARCHAR(16) NOT NULL DEFAULT 'IMAGE',
    ADD COLUMN video_url     TEXT,
    ADD COLUMN duration_ms   INT,
    ADD COLUMN caption       TEXT,
    ADD COLUMN overlays_json TEXT,
    ADD COLUMN background    VARCHAR(32),
    ADD COLUMN audience      VARCHAR(16) NOT NULL DEFAULT 'ALL',
    ADD COLUMN deleted_at    TIMESTAMPTZ;

-- A text card has no media, so the original NOT NULL can't stand. The CHECK
-- below is what actually keeps a frame well-formed.
ALTER TABLE social.story_frame
    ALTER COLUMN image_url DROP NOT NULL;

ALTER TABLE social.story_frame
    ADD CONSTRAINT story_frame_media_type_chk
        CHECK (media_type IN ('IMAGE', 'VIDEO', 'TEXT')),
    ADD CONSTRAINT story_frame_audience_chk
        CHECK (audience IN ('ALL', 'CLOSE_FRIENDS')),
    -- IMAGE needs its image; VIDEO needs its stream (image_url is then the
    -- poster frame, optional); TEXT needs neither.
    ADD CONSTRAINT story_frame_media_present_chk
        CHECK (
            (media_type = 'IMAGE' AND image_url IS NOT NULL)
            OR (media_type = 'VIDEO' AND video_url IS NOT NULL)
            OR (media_type = 'TEXT')
        );

-- The rings read is "this author's live frames, oldest first" — every query
-- now also excludes soft-deleted rows, so index only the live ones.
CREATE INDEX story_frame_live_idx
    ON social.story_frame (author_id, created_at)
    WHERE deleted_at IS NULL;

-- The viewers list ("Seen by", newest first) needs a time, which the original
-- membership-only table never stored. Backfilled to now() for existing rows —
-- they predate the feature and only affect ordering among themselves.
ALTER TABLE social.story_view
    ADD COLUMN viewed_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE INDEX story_view_frame_idx ON social.story_view (frame_id, viewed_at DESC);

COMMENT ON COLUMN social.story_frame.overlays_json IS
    'Client-authored overlay spec (text/sticker placements), opaque to the server.';
COMMENT ON COLUMN social.story_frame.audience IS
    'ALL, or CLOSE_FRIENDS — enforced against social.close_friend (V13).';
