-- Tagging people (@handle) in captions and comments, and replying to a comment.
--
-- **Why mentions are rows and not just text.** The naive version is to leave the
-- "@amina" in the body and re-resolve it on every render. This app lets people
-- change their handle (V7), so that link breaks the moment they do — and the
-- notification fan-out would have to re-parse the text anyway. Resolving once,
-- at write time, is what makes "tagged" a fact about the post rather than a
-- guess about its spelling.
--
-- `handle` is stored alongside `profile_id` deliberately: it is the handle *as
-- written*, which is the token the client has to find in the body to underline.
-- The current handle is whatever the profile says today; this column is history,
-- and must not be updated when someone renames.
--
-- **One table for both targets.** A caption mention and a comment mention differ
-- only in what they hang off, so `target_kind` is half the key rather than two
-- near-identical tables. No FK on `target_id` for the same reason — one column
-- cannot reference two tables, and the delete cascade is handled below.

CREATE TABLE social.mention (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),

    -- POST | COMMENT. Not an enum type: a third taggable surface (a story
    -- caption is the obvious next one) should not be a migration that rewrites
    -- a type this table's indexes depend on.
    target_kind VARCHAR(16) NOT NULL,
    target_id   UUID        NOT NULL,

    -- Who was tagged, resolved server-side at write time — never a client claim.
    profile_id  UUID        NOT NULL,
    -- The handle as typed, so the renderer can locate the span in the body.
    handle      VARCHAR(60) NOT NULL,

    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT mention_target_kind_chk CHECK (target_kind IN ('POST', 'COMMENT'))
);

-- The read path: every mention on a batch of posts/comments being decorated.
CREATE INDEX mention_target_idx ON social.mention (target_kind, target_id);
-- The other direction: "posts I'm tagged in", which the profile tab will want.
CREATE INDEX mention_profile_idx ON social.mention (profile_id, created_at DESC);
-- Tagging the same person twice in one caption is one tag, not two notifications.
CREATE UNIQUE INDEX mention_unique_idx ON social.mention (target_kind, target_id, profile_id);

-- Replies. One level only, by design: `parent_id` always points at a top-level
-- comment, and a reply to a reply re-points to that same parent (the service
-- enforces it). Deep trees are a rendering problem nobody on a phone has ever
-- wanted solved — Instagram, Threads and YouTube all flatten at depth 1.
ALTER TABLE social.comment
    ADD COLUMN parent_id   UUID REFERENCES social.comment (id) ON DELETE CASCADE,
    -- Denormalised so the thread list can say "3 replies" without a join per row.
    ADD COLUMN reply_count INT NOT NULL DEFAULT 0;

-- Loading one comment's replies, oldest first (a thread reads top-down).
CREATE INDEX comment_parent_created_idx ON social.comment (parent_id, created_at);

-- The existing (post_id, created_at) index still serves the top-level query,
-- but that query now filters parent_id IS NULL — a partial index keeps it exact
-- and stays small, since replies are the majority of rows on a busy post.
CREATE INDEX comment_post_toplevel_idx
    ON social.comment (post_id, created_at) WHERE parent_id IS NULL;

-- Deleting a post already cascades to its comments; mentions hang off both and
-- have no FK to cascade through, so they are swept here instead.
CREATE OR REPLACE FUNCTION social.delete_post_mentions() RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM social.mention WHERE target_kind = 'POST' AND target_id = OLD.id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER post_mentions_cleanup
    BEFORE DELETE ON social.post
    FOR EACH ROW EXECUTE FUNCTION social.delete_post_mentions();

CREATE OR REPLACE FUNCTION social.delete_comment_mentions() RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM social.mention WHERE target_kind = 'COMMENT' AND target_id = OLD.id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER comment_mentions_cleanup
    BEFORE DELETE ON social.comment
    FOR EACH ROW EXECUTE FUNCTION social.delete_comment_mentions();

-- Tag limits (SPECS §14 config registry). Compiled-in defaults match, so an
-- empty config table behaves identically; the rows make the numbers visible.
INSERT INTO platform.config (key, value, note) VALUES
    ('social.max.mentions.per.post', '20',
     'People taggable in one caption — a spam ceiling, not a technical one'),
    ('social.max.mentions.per.comment', '10',
     'People taggable in one comment');
