-- Phase 2b · Milestone 1: economy vertical (marketplace listings + saves).
-- seller_id / user_id reference profile.user_profile as plain UUIDs — no
-- foreign keys across schemas, ever (ARCHITECTURE.md §3).

CREATE SCHEMA IF NOT EXISTS economy;

CREATE TABLE economy.listing (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id      UUID        NOT NULL,
    title          VARCHAR(140) NOT NULL,
    price_cents    BIGINT,                              -- null = "price on ask"
    currency       VARCHAR(3)  NOT NULL DEFAULT 'USD',
    category       VARCHAR(60) NOT NULL DEFAULT 'Home',
    condition      VARCHAR(40) NOT NULL DEFAULT 'Good',
    location_label VARCHAR(80) NOT NULL DEFAULT 'nearby',
    description    TEXT        NOT NULL DEFAULT '',
    active         BOOLEAN     NOT NULL DEFAULT true,
    save_count     INT         NOT NULL DEFAULT 0,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX listing_active_created_idx ON economy.listing (active, created_at DESC);
CREATE INDEX listing_seller_created_idx ON economy.listing (seller_id, created_at DESC);
CREATE INDEX listing_category_idx       ON economy.listing (category);

CREATE TABLE economy.listing_media (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id UUID NOT NULL REFERENCES economy.listing (id) ON DELETE CASCADE,
    sort_order INT  NOT NULL,
    image_url  TEXT NOT NULL
);
CREATE INDEX listing_media_listing_idx ON economy.listing_media (listing_id);

CREATE TABLE economy.saved_listing (
    listing_id UUID        NOT NULL REFERENCES economy.listing (id) ON DELETE CASCADE,
    user_id    UUID        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (listing_id, user_id)
);
CREATE INDEX saved_listing_user_idx ON economy.saved_listing (user_id, created_at DESC);
