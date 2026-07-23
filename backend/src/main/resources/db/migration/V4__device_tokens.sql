-- APNs device tokens for push delivery of activity notifications. One row per
-- (device) token; a token maps to exactly one profile (re-registered on login).

CREATE TABLE notifications.device_token (
    id         UUID        PRIMARY KEY,
    profile_id UUID        NOT NULL,
    token      TEXT        NOT NULL UNIQUE,
    platform   VARCHAR(16) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX device_token_profile_idx ON notifications.device_token (profile_id);
