-- Phase 2e · Milestone 1: business profiles (ARCHITECTURE.md §2b decision 1, SPECS.md §8).
--
-- A business IS a profile. Everything the social graph already does — follows,
-- feed, stories, watch, notifications, search later — then works for a business
-- with zero changes, because there is nothing new to work on: a business row
-- lives in the same table as a person's.
--
-- Two consequences the schema has to absorb:
--   • a business has no Cognito user of its own (its owner signs in), so
--     cognito_sub stops being mandatory. Postgres lets a UNIQUE column hold
--     many NULLs, so the uniqueness that protects sign-in is untouched.
--   • the fields only a business has (address, contact, hours) go in an
--     extension table rather than as always-null columns on every person.
--     `category` and `bio` are NOT duplicated here — a business reuses the
--     ones every profile already has.

ALTER TABLE profile.user_profile
    ALTER COLUMN cognito_sub DROP NOT NULL,
    ADD COLUMN kind VARCHAR(16) NOT NULL DEFAULT 'PERSON';

CREATE TABLE profile.business_profile (
    profile_id       UUID         PRIMARY KEY REFERENCES profile.user_profile (id) ON DELETE CASCADE,
    -- The person who acts as this business. Same schema, so a real FK is fine.
    owner_profile_id UUID         NOT NULL REFERENCES profile.user_profile (id),

    contact_phone    VARCHAR(32)  NOT NULL DEFAULT '',
    contact_email    VARCHAR(160) NOT NULL DEFAULT '',
    website_url      VARCHAR(400),

    address_line     VARCHAR(200) NOT NULL DEFAULT '',
    city             VARCHAR(80)  NOT NULL DEFAULT '',
    country          VARCHAR(60)  NOT NULL DEFAULT '',
    latitude         DOUBLE PRECISION,
    longitude        DOUBLE PRECISION,

    -- Opening hours as authored JSON so the shape can grow (per-day ranges,
    -- exceptions) without a migration; rendered read-only by the app.
    opening_hours    TEXT,

    -- Earned only through a partner approval (KYC'd). Never sold, never set by
    -- the owner — hence no path to it on the owner-scoped edit endpoint.
    verified         BOOLEAN      NOT NULL DEFAULT FALSE,

    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX business_profile_owner_idx ON profile.business_profile (owner_profile_id);

-- Which public identity an application commerce-enables. Plain UUID: the
-- partner schema never points into another schema with a foreign key
-- (ARCHITECTURE.md §4). Null on every application written before this ran.
ALTER TABLE partner.partner_account
    ADD COLUMN business_profile_id UUID;
