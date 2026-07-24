-- Phase 2b · M4 follow-up: drop the demo catalog, and give delivery real addresses.
--
-- V8 is left untouched on purpose — it has already run against prod, and
-- rewriting an applied migration breaks Flyway's checksum. A fresh database
-- therefore inserts the seed and then deletes it here; the end state is the
-- same empty catalog either way.

-- 1. Remove the seeded demo restaurants. Orders point at merchants with a plain
--    foreign key, so the orders placed against them (test data only — the seed
--    only ever existed on this deploy) go first; order_line cascades from there.
DELETE FROM delivery.customer_order
 WHERE merchant_id IN (
   'd0000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000002',
   'd0000000-0000-4000-8000-000000000003','d0000000-0000-4000-8000-000000000004',
   'd0000000-0000-4000-8000-000000000005','d0000000-0000-4000-8000-000000000006');

-- Categories, tags, sections and items all cascade off the merchant row.
DELETE FROM delivery.merchant
 WHERE id IN (
   'd0000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000002',
   'd0000000-0000-4000-8000-000000000003','d0000000-0000-4000-8000-000000000004',
   'd0000000-0000-4000-8000-000000000005','d0000000-0000-4000-8000-000000000006');

-- 2. Saved delivery addresses. user_id references profile.user_profile as a
--    plain UUID — no foreign keys across schemas (ARCHITECTURE.md §3).
CREATE TABLE delivery.address (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID         NOT NULL,
    label      VARCHAR(40)  NOT NULL,             -- "Home", "Work", "Mum's"
    line1      VARCHAR(160) NOT NULL,             -- street line
    note       VARCHAR(120) NOT NULL DEFAULT '',  -- floor, door code, landmark
    latitude   DOUBLE PRECISION,
    longitude  DOUBLE PRECISION,
    is_default BOOLEAN      NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX address_user_idx ON delivery.address (user_id, created_at DESC);
-- At most one default per user, enforced by the database rather than by hope.
CREATE UNIQUE INDEX address_user_default_idx
    ON delivery.address (user_id) WHERE is_default;

-- 3. The order keeps its own copy of where it went. Same rule as the line
--    prices: editing or deleting an address later must not rewrite an old
--    receipt, so there is deliberately no foreign key back to address.
ALTER TABLE delivery.customer_order
    ADD COLUMN address_id        UUID,
    ADD COLUMN address_line      VARCHAR(160)     NOT NULL DEFAULT '',
    ADD COLUMN address_note      VARCHAR(120)     NOT NULL DEFAULT '',
    ADD COLUMN address_latitude  DOUBLE PRECISION,
    ADD COLUMN address_longitude DOUBLE PRECISION;
