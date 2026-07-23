-- Milestone: orphan-upload cleanup. Presigned uploads land directly in S3, so
-- a key that is minted but never referenced by a post/story/avatar/message is an
-- orphan (wasted storage). We record every presigned key here and mark it
-- referenced when a module persists its URL; a scheduled sweep reports (and,
-- once enabled, deletes) rows still unreferenced after a grace period.

CREATE SCHEMA IF NOT EXISTS media;

CREATE TABLE media.upload_object (
    object_key    VARCHAR(500) PRIMARY KEY,
    profile_id    UUID         NOT NULL,
    content_type  VARCHAR(100) NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL,
    referenced_at TIMESTAMPTZ
);

-- The sweep query: oldest still-unreferenced keys first. Partial index keeps it
-- small — referenced rows (the vast majority over time) are excluded.
CREATE INDEX upload_object_unreferenced_idx
    ON media.upload_object (created_at)
    WHERE referenced_at IS NULL;
