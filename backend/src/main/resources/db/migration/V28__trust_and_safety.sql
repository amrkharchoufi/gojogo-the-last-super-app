-- Phase 2e · Milestone 5: the trust & safety baseline (SPECS.md §10–§11).
--
-- Everything before this migration assumed people behave. Nothing in the app
-- could stop a stranger following you around, nothing could tell us a post is
-- abusive, and an account, once created, could never be destroyed. Those three
-- gaps are not features — App Store guideline 1.2 makes report + block + a way
-- out a condition of shipping user-generated content at all.
--
-- Four things live here: blocks, a report queue, a soft-hide flag on every
-- surface that carries user content, and the account-deletion clock.

-- ---------------------------------------------------------------------------
-- 1. Blocking
-- ---------------------------------------------------------------------------
--
-- **One row, two directions.** Only the blocker's row exists — blocking is
-- something one person does — but the *effect* is symmetric: neither party sees
-- the other anywhere. A one-directional filter would leave the person you
-- blocked reading your posts, which is precisely the thing you blocked them to
-- stop. So every read filters on "a block exists in either direction", which is
-- why blocked_id gets an index of its own: the reverse lookup runs as often as
-- the forward one.
--
-- It lives in `social` next to `follow` because a block *is* a graph edge and
-- has to be removed from the follow graph in the same transaction. Splitting the
-- two across modules would make "block also unfollows" eventually consistent —
-- and a safety feature that is briefly wrong is a safety feature that failed.

-- Plain UUIDs, no foreign key into profile.user_profile — the same rule
-- social.follow has followed since V2 and ARCHITECTURE §4 states: no FK crosses
-- a schema boundary, because that is the line a module is extracted along.

CREATE TABLE social.block (
    blocker_id UUID        NOT NULL,
    blocked_id UUID        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (blocker_id, blocked_id),
    CONSTRAINT block_not_self_chk CHECK (blocker_id <> blocked_id)
);

-- "Who blocked me" — read on every feed, comment thread and profile view, so it
-- is not the incidental direction.
CREATE INDEX block_blocked_idx ON social.block (blocked_id);

-- ---------------------------------------------------------------------------
-- 2. Reports
-- ---------------------------------------------------------------------------
--
-- A platform module rather than a table per vertical: the queue a human works is
-- one queue, and a moderator should not have to know that a reported photo and a
-- reported listing were filed in different places. What the module deliberately
-- does *not* own is the content — it stores a pointer (kind + id) and asks the
-- vertical that owns that kind to look it up and to act on it.

CREATE SCHEMA IF NOT EXISTS moderation;

CREATE TABLE moderation.report (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),

    reporter_id     UUID         NOT NULL,

    -- POST | COMMENT | STORY | VIDEO | PROFILE | LISTING | MERCHANT. Not an
    -- enum type: every new vertical adds a kind, and that should be a new
    -- handler bean rather than a migration that rewrites a type this table's
    -- unique index depends on.
    target_kind     VARCHAR(24)  NOT NULL,
    target_id       UUID         NOT NULL,
    -- Whose content it is, resolved from the vertical at report time. Copied
    -- rather than looked up later so the queue still names an owner after the
    -- content is removed — and so "three reports against the same account this
    -- week" is one query instead of a fan-out.
    target_owner_id UUID,

    reason          VARCHAR(32)  NOT NULL,
    note            VARCHAR(1000) NOT NULL DEFAULT '',

    -- OPEN | ACTIONED | DISMISSED.
    status          VARCHAR(16)  NOT NULL DEFAULT 'OPEN',
    -- HIDE | REMOVE | SUSPEND | RESTORE, null while OPEN or DISMISSED.
    action          VARCHAR(16),
    -- The operator's email when they signed in as themselves, or a marker for
    -- the break-glass token. A moderation decision that cannot name a decider
    -- is worth seeing as such.
    reviewed_by     VARCHAR(200),
    reviewed_at     TIMESTAMPTZ,
    review_note     VARCHAR(1000),

    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT report_status_chk CHECK (status IN ('OPEN', 'ACTIONED', 'DISMISSED')),
    CONSTRAINT report_action_chk CHECK (action IS NULL
        OR action IN ('HIDE', 'REMOVE', 'SUSPEND', 'RESTORE'))
);

-- Reporting the same thing twice is one report, not two queue items. The write
-- path turns the collision into "already reported" rather than an error: a
-- person who taps report again wants reassurance, not a 409.
CREATE UNIQUE INDEX report_once_per_reporter_idx
    ON moderation.report (reporter_id, target_kind, target_id);

-- The queue: oldest open first, because the thing nobody has looked at yet is
-- the thing that matters.
CREATE INDEX report_open_idx ON moderation.report (status, created_at);
-- Every report against one piece of content — actioning one resolves them all.
CREATE INDEX report_target_idx ON moderation.report (target_kind, target_id);
-- Every report against one account, which is what a suspension decision reads.
CREATE INDEX report_owner_idx ON moderation.report (target_owner_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 3. Hiding content, softly
-- ---------------------------------------------------------------------------
--
-- **A hide is reversible and a delete is not**, which is the entire reason both
-- exist. A moderator working a queue at speed will be wrong sometimes; the
-- default action should be the one that can be undone, and the author should
-- still see their own post so that "why has nobody replied" has an answer.
--
-- A timestamp rather than a boolean: knowing *when* something was hidden is the
-- difference between an appeal that can be assessed and one that can't. NULL is
-- the overwhelmingly common value, so these columns cost nothing on disk.

ALTER TABLE social.post        ADD COLUMN hidden_at TIMESTAMPTZ;
ALTER TABLE social.comment     ADD COLUMN hidden_at TIMESTAMPTZ;
ALTER TABLE social.story_frame ADD COLUMN hidden_at TIMESTAMPTZ;
ALTER TABLE watch.video        ADD COLUMN hidden_at TIMESTAMPTZ;
ALTER TABLE economy.listing    ADD COLUMN hidden_at TIMESTAMPTZ;

-- No index on any of them. Every read that filters hidden content is already
-- constrained by an author, a post, or a keyset window, and a column that is
-- NULL for ~100% of rows is one Postgres will not use an index on anyway.

-- ---------------------------------------------------------------------------
-- 4. Account deletion
-- ---------------------------------------------------------------------------
--
-- Deletion is a clock, not an event. `deletion_requested_at` starts a grace
-- period (Cognito sign-in is disabled the same instant, so the account is
-- already gone from the user's point of view); `anonymized_at` is set by the
-- sweep once the grace expires and the profile has actually been scrubbed.
--
-- **The content is not deleted, the authorship is.** Removing a person's posts
-- takes their replies, other people's threads and half a conversation with them
-- — a tombstoned author is what every social product settled on, and this
-- codebase already renders a missing profile as "Deleted user". Ledger rows in
-- `payments` are kept untouched: they are a financial record and not ours to
-- erase.

ALTER TABLE profile.user_profile
    ADD COLUMN deletion_requested_at TIMESTAMPTZ,
    ADD COLUMN anonymized_at         TIMESTAMPTZ;

-- The sweep's only query: whose grace has run out. Partial, because the column
-- is null for every account that isn't leaving.
CREATE INDEX user_profile_deletion_idx
    ON profile.user_profile (deletion_requested_at)
    WHERE deletion_requested_at IS NOT NULL AND anonymized_at IS NULL;

-- ---------------------------------------------------------------------------
-- 5. Policy knobs (SPECS §14)
-- ---------------------------------------------------------------------------
-- Compiled-in defaults match these exactly, so an empty config table behaves
-- identically; the rows exist so the numbers are visible and changeable without
-- a deploy.

INSERT INTO platform.config (key, value, note) VALUES
    ('moderation.deletion.grace.days', '30',
     'Days between "delete my account" and the profile being scrubbed'),
    ('moderation.report.note.max', '1000',
     'Characters a reporter may write — matches the column'),
    ('social.max.blocks', '5000',
     'Accounts one person may block; a spam ceiling, not a technical one');
