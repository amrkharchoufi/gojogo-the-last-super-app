-- Stories · Slice 3: what survives the 24 hours — the archive, highlights, and
-- the close-friends audience the V11 `audience` column has been carrying.

-- Close friends is the author's own list, not a mutual relationship and not a
-- kind of follow: you can put someone on it who doesn't follow you back.
CREATE TABLE social.close_friend (
    owner_id   UUID        NOT NULL,
    friend_id  UUID        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (owner_id, friend_id)
);
-- The rings read asks the reverse question — "whose close-friends list am I
-- on?" — so index that direction too.
CREATE INDEX close_friend_friend_idx ON social.close_friend (friend_id);

CREATE TABLE social.story_highlight (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id   UUID        NOT NULL,
    title      VARCHAR(60) NOT NULL,
    cover_url  TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
CREATE INDEX story_highlight_owner_idx ON social.story_highlight (owner_id, created_at DESC);

-- A highlight pins frames past their expiry. This is why story_frame deletes
-- softly (V11) — a hard delete would cascade the frame out from under every
-- highlight holding it.
CREATE TABLE social.story_highlight_frame (
    highlight_id UUID NOT NULL REFERENCES social.story_highlight (id) ON DELETE CASCADE,
    frame_id     UUID NOT NULL REFERENCES social.story_frame (id) ON DELETE CASCADE,
    sort_order   INT  NOT NULL DEFAULT 0,
    PRIMARY KEY (highlight_id, frame_id)
);
