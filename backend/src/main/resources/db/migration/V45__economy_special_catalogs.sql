-- Phase 5 · Milestone 2: special catalogs (SPECS §6) — digital products and
-- ownership-transfer listings. Both are kinds with extra tables, not new
-- modules.

-- A listing can now be an ownership transfer (a car, a numbered thing): the
-- C2C shape plus a serial and a supervised handover. STANDARD listings are
-- untouched.
ALTER TABLE economy.listing ADD COLUMN kind VARCHAR(24) NOT NULL DEFAULT 'STANDARD';
ALTER TABLE economy.listing ADD COLUMN vin_serial VARCHAR(80);

-- The paperwork a transfer is argued from — title documents, uploaded by the
-- seller into the private prefix (MediaDocumentApi; object keys only, never
-- public URLs), read by the parties and the reviewer through short-lived
-- signed GETs.
CREATE TABLE economy.transfer_document (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    transfer_id UUID        NOT NULL,
    object_key  TEXT        NOT NULL,
    label       VARCHAR(80) NOT NULL DEFAULT '',
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX transfer_document_transfer_idx ON economy.transfer_document (transfer_id);

-- The transfer workflow (SPECS §6): INQUIRY → OFFER_ACCEPTED → PAYMENT_HELD →
-- DOCS_CONFIRMED (human checkpoint) → TRANSFERRED → RELEASED, either side
-- cancelling before DOCS_CONFIRMED for a full refund.
CREATE TABLE economy.ownership_transfer (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id        UUID        NOT NULL,
    seller_id         UUID        NOT NULL,
    buyer_id          UUID        NOT NULL,
    state             VARCHAR(24) NOT NULL DEFAULT 'INQUIRY',
    price_cents       BIGINT,
    -- Above the CONFIG wallet cap: the escrow is refused and an operator
    -- settles it by hand. The flag is what the admin queue reads.
    flagged_manual    BOOLEAN     NOT NULL DEFAULT false,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    accepted_at       TIMESTAMPTZ,
    paid_at           TIMESTAMPTZ,
    docs_confirmed_at TIMESTAMPTZ,
    docs_confirmed_by VARCHAR(120),
    transferred_at    TIMESTAMPTZ,
    released_at       TIMESTAMPTZ,
    cancelled_at      TIMESTAMPTZ,
    cancel_note       TEXT        NOT NULL DEFAULT ''
);
CREATE INDEX ownership_transfer_buyer_idx  ON economy.ownership_transfer (buyer_id, created_at DESC);
CREATE INDEX ownership_transfer_seller_idx ON economy.ownership_transfer (seller_id, created_at DESC);
CREATE INDEX ownership_transfer_state_idx  ON economy.ownership_transfer (state, created_at DESC);
-- One escrow per thing: many buyers may inquire, but only one transfer can
-- hold money against a listing at a time.
CREATE UNIQUE INDEX ownership_transfer_live_idx ON economy.ownership_transfer (listing_id)
    WHERE state IN ('PAYMENT_HELD', 'DOCS_CONFIRMED', 'TRANSFERRED');

-- The digital half. A DIGITAL product carries one asset in the private prefix;
-- what a purchase grants is the asset's entitlement kind.
CREATE TABLE economy.digital_asset (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id       UUID         NOT NULL UNIQUE REFERENCES economy.product (id) ON DELETE CASCADE,
    object_key       TEXT         NOT NULL,
    file_name        VARCHAR(140) NOT NULL DEFAULT '',
    content_type     VARCHAR(100) NOT NULL DEFAULT 'application/octet-stream',
    -- DOWNLOAD | LICENSE. SUBSCRIPTION is reserved (SPECS §6) and lands with a
    -- Stripe-subscription mirror that does not exist yet.
    entitlement_kind VARCHAR(16)  NOT NULL DEFAULT 'DOWNLOAD',
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- What a buyer owns after a digital purchase. Downloads are re-issued as
-- short-lived signed GETs for as long as the row exists; a license carries its
-- generated key.
CREATE TABLE economy.entitlement (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL,
    product_id  UUID        NOT NULL,
    order_id    UUID        NOT NULL,
    kind        VARCHAR(16) NOT NULL,
    license_key VARCHAR(64),
    expires_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX entitlement_user_idx ON economy.entitlement (user_id, created_at DESC);
CREATE INDEX entitlement_order_idx ON economy.entitlement (order_id);
