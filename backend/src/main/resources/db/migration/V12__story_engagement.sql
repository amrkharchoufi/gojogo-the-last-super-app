-- Stories · Slice 2: the engagement loop — react, reply, see who watched, mute.

-- One reaction per person per frame: tapping a second emoji replaces the first
-- rather than stacking, which is what the PK enforces.
CREATE TABLE social.story_reaction (
    frame_id   UUID        NOT NULL REFERENCES social.story_frame (id) ON DELETE CASCADE,
    viewer_id  UUID        NOT NULL,
    emoji      VARCHAR(16) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (frame_id, viewer_id)
);

-- A reply to a story. Modelled as a comment row (it has an author, a body and a
-- time), but read back with Instagram's privacy: the frame's author sees every
-- reply, a viewer sees only their own. See StoryCommentService.
CREATE TABLE social.story_comment (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    frame_id   UUID        NOT NULL REFERENCES social.story_frame (id) ON DELETE CASCADE,
    author_id  UUID        NOT NULL,
    text       TEXT        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX story_comment_frame_idx ON social.story_comment (frame_id, created_at);
CREATE INDEX story_comment_author_idx ON social.story_comment (frame_id, author_id);

-- Muting hides someone's ring without unfollowing them, so it belongs here and
-- not on the follow row: you can mute a person you don't follow back, and an
-- unfollow/refollow shouldn't silently un-mute them.
CREATE TABLE social.story_mute (
    muter_id   UUID        NOT NULL,
    muted_id   UUID        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (muter_id, muted_id)
);
