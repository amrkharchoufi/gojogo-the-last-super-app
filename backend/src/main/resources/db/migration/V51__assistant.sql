-- Phase 6 · Madeleine M2: the assistant module (MADELEINE.md §3) — conversations,
-- the message ledger, background tasks, and the pending-action wall.
-- Cross-schema references are plain UUIDs, never foreign keys.

CREATE SCHEMA IF NOT EXISTS assistant;

-- One thread with Madeleine. `title` is written by the sidekick after the first
-- exchange and is empty until then, which is what the list screen draws a
-- placeholder for.
CREATE TABLE assistant.conversation (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID         NOT NULL,
    title          VARCHAR(120) NOT NULL DEFAULT '',
    state          VARCHAR(16)  NOT NULL DEFAULT 'ACTIVE',
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    last_active_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX assistant_conversation_user_idx
    ON assistant.conversation (user_id, last_active_at DESC);

-- The ledger, and the thing that makes a route change cheap: MADELEINE.md §7
-- persists what replays the story, never the token stream. A row is what the
-- user said, what Madeleine said, or that a tool ran and what came back in
-- summary — so a mid-flight model or route swap loses at most one turn and
-- never a conversation.
--
-- `turn_id` groups every row one user message produced. The task ledger and the
-- replay view both read by it, which is why it is indexed rather than derived.
CREATE TABLE assistant.message (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id     UUID        NOT NULL REFERENCES assistant.conversation (id) ON DELETE CASCADE,
    turn_id             UUID        NOT NULL,
    seq                 INT         NOT NULL,
    role                VARCHAR(16) NOT NULL,
    content             TEXT        NOT NULL DEFAULT '',
    -- Set on TOOL rows only. `tool_args` is what the model asked for, kept
    -- because "why did she search for that" is the first debugging question;
    -- `tool_result_summary` is the trimmed result that entered context, not the
    -- raw payload, which is deliberately not stored anywhere.
    tool_name           VARCHAR(64),
    tool_args           TEXT,
    tool_result_summary TEXT,
    -- Token instrumentation (MADELEINE-INFERENCE.md §6/§10.9), stamped on the
    -- MADELEINE row that closes a turn. §6's switch trigger is worthless
    -- without it and retrofitting counters into a working loop is how they end
    -- up approximate — so they are written from the first turn this module ever
    -- runs. Nullable because a USER or TOOL row has no model call behind it.
    model               VARCHAR(120),
    input_tokens        INT,
    output_tokens       INT,
    step_count          INT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT assistant_message_seq_unique UNIQUE (conversation_id, seq)
);
CREATE INDEX assistant_message_turn_idx ON assistant.message (turn_id, seq);

-- The autonomy unit (§7). The runner is M6; the table is here because the
-- ledger, the actions and the messages all reference a task and a schema that
-- grows a column per milestone is a schema nobody can read.
CREATE TABLE assistant.task (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL,
    conversation_id UUID        REFERENCES assistant.conversation (id) ON DELETE SET NULL,
    goal            TEXT        NOT NULL,
    state           VARCHAR(24) NOT NULL DEFAULT 'QUEUED',
    -- The step plan as the model laid it out, JSON in a text column: it is
    -- rendered by the ledger screen and never queried into.
    step_plan       TEXT        NOT NULL DEFAULT '[]',
    failure_reason  TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at     TIMESTAMPTZ
);
CREATE INDEX assistant_task_user_idx ON assistant.task (user_id, created_at DESC);
CREATE INDEX assistant_task_state_idx ON assistant.task (state, created_at);

-- A side effect the model asked for and may not have (§5). Every WRITE_GATED
-- tool call lands here instead of executing: the executor consults the registry,
-- sees the class, and writes a row. There is no code path from model output to
-- the vertical call, which is why this table is the security model rather than a
-- queue.
--
-- `confirm_token` is the wall. It is minted here, travels socket -> client ->
-- POST /actions/{id}/approve, and is NEVER serialised into model context — the
-- model cannot approve its own action because it cannot name the token. M4
-- builds the approval flow on top of this table; M2 only ever writes PENDING.
CREATE TABLE assistant.action (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID        NOT NULL REFERENCES assistant.conversation (id) ON DELETE CASCADE,
    task_id         UUID        REFERENCES assistant.task (id) ON DELETE SET NULL,
    turn_id         UUID        NOT NULL,
    tool_name       VARCHAR(64) NOT NULL,
    args            TEXT        NOT NULL DEFAULT '{}',
    -- What the confirm card says, in the user's own terms. Written server-side;
    -- the amount, when there is one, is computed by the owning vertical's quote
    -- path and never by the model.
    summary         TEXT        NOT NULL,
    amount_minor    BIGINT,
    currency        VARCHAR(3),
    state           VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    confirm_token   UUID        NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ NOT NULL,
    decided_at      TIMESTAMPTZ
);
CREATE INDEX assistant_action_conversation_idx
    ON assistant.action (conversation_id, created_at DESC);
CREATE INDEX assistant_action_expiry_idx ON assistant.action (state, expires_at);
