-- Schema-per-module. No cross-schema foreign keys, ever (see ARCHITECTURE.md §3).
CREATE SCHEMA IF NOT EXISTS profile;
CREATE SCHEMA IF NOT EXISTS social;
CREATE SCHEMA IF NOT EXISTS media;

CREATE TABLE profile.user_profile (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cognito_sub  VARCHAR(64)  NOT NULL UNIQUE,
    email        VARCHAR(320),
    display_name VARCHAR(120),
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);
