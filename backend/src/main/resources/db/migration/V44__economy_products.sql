-- Phase 5 · Milestone 1: merchant products in economy (SPECS §6).
-- A product is a provisioned seller's catalog entry with variants and counted
-- stock; a C2C listing stays exactly what it was — a listing is not a product.
-- All cross-schema references are plain UUIDs, never foreign keys
-- (ARCHITECTURE.md §3).

-- The seller registry: what a partner SELLER approval provisions
-- (economy.SellerProvisioningApi, the MerchantProvisioningApi pattern).
-- Shipping and tax are the flat per-merchant config SPECS §6 settles for —
-- no tax engine.
CREATE TABLE economy.seller (
    id                       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id            UUID         NOT NULL UNIQUE,
    display_name             VARCHAR(120) NOT NULL,
    logo_url                 TEXT,
    shipping_flat_cents      INT          NOT NULL DEFAULT 0,
    -- 0 = shipping is never free
    free_shipping_over_cents INT          NOT NULL DEFAULT 0,
    tax_bps                  INT          NOT NULL DEFAULT 0,
    suspended                BOOLEAN      NOT NULL DEFAULT false,
    created_at               TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE economy.product (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id    UUID         NOT NULL REFERENCES economy.seller (id),
    name         VARCHAR(140) NOT NULL,
    description  TEXT         NOT NULL DEFAULT '',
    category     VARCHAR(60)  NOT NULL DEFAULT 'General',
    brand        VARCHAR(80),
    -- PHYSICAL today; DIGITAL arrives with Phase 5 M2 on this same column.
    kind         VARCHAR(16)  NOT NULL DEFAULT 'PHYSICAL',
    -- Free-form spec sheet the seller fills in ("material": "wool"), rendered
    -- as rows. JSON object, opaque to the server.
    specs        TEXT         NOT NULL DEFAULT '{}',
    active       BOOLEAN      NOT NULL DEFAULT true,
    hidden_at    TIMESTAMPTZ,
    -- The review aggregate, cached here (SPECS §6): sum/count rather than an
    -- average so two concurrent reviews add instead of averaging an average.
    rating_sum   BIGINT       NOT NULL DEFAULT 0,
    rating_count INT          NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ
);
CREATE INDEX product_seller_idx   ON economy.product (seller_id, created_at DESC);
CREATE INDEX product_browse_idx   ON economy.product (active, created_at DESC);
CREATE INDEX product_category_idx ON economy.product (category);

CREATE TABLE economy.product_media (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES economy.product (id) ON DELETE CASCADE,
    sort_order INT  NOT NULL,
    image_url  TEXT NOT NULL
);
CREATE INDEX product_media_product_idx ON economy.product_media (product_id);

-- The SKU level: what is actually priced, stocked and bought. Every product
-- has at least one ("Default" when the seller doesn't care about options).
CREATE TABLE economy.product_variant (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id  UUID         NOT NULL REFERENCES economy.product (id) ON DELETE CASCADE,
    sku         VARCHAR(64),
    -- The option values as one display string ("Blue / L") — the closed set of
    -- option axes is a storefront-tooling concern, not an order-integrity one.
    label       VARCHAR(120) NOT NULL,
    price_cents BIGINT       NOT NULL,
    stock       INT          NOT NULL DEFAULT 0,
    active      BOOLEAN      NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX product_variant_product_idx ON economy.product_variant (product_id);

-- SPECS §6's shared promotion shape, economy's copy (delivery.promotion is the
-- first). FREE_SHIPPING is the fee-line discount, same mechanism as delivery's
-- FREE_DELIVERY.
CREATE TABLE economy.product_promotion (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id          UUID         NOT NULL REFERENCES economy.seller (id),
    code               VARCHAR(40),
    label              VARCHAR(120) NOT NULL DEFAULT '',
    kind               VARCHAR(16)  NOT NULL,
    value_bps          INT          NOT NULL DEFAULT 0,
    amount_cents       INT          NOT NULL DEFAULT 0,
    min_basket_cents   INT          NOT NULL DEFAULT 0,
    max_discount_cents INT          NOT NULL DEFAULT 0,
    per_user_limit     INT          NOT NULL DEFAULT 0,
    starts_at          TIMESTAMPTZ,
    ends_at            TIMESTAMPTZ,
    active             BOOLEAN      NOT NULL DEFAULT true,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX product_promotion_seller_idx ON economy.product_promotion (seller_id, active);

CREATE TABLE economy.product_promotion_redemption (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    promotion_id UUID        NOT NULL REFERENCES economy.product_promotion (id) ON DELETE CASCADE,
    user_id      UUID        NOT NULL,
    order_id     UUID        NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX product_promotion_redemption_user_idx
    ON economy.product_promotion_redemption (promotion_id, user_id);

-- One checkout against one seller (SPECS §6: one cart per seller context).
-- Server-priced, wallet-held at placement, settled when the buyer confirms
-- receipt. Line snapshots survive the catalog changing under an old order.
CREATE TABLE economy.product_order (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    buyer_id        UUID         NOT NULL,
    seller_id       UUID         NOT NULL REFERENCES economy.seller (id),
    status          VARCHAR(16)  NOT NULL DEFAULT 'PLACED',
    subtotal_cents  INT          NOT NULL,
    discount_cents  INT          NOT NULL DEFAULT 0,
    shipping_cents  INT          NOT NULL DEFAULT 0,
    tax_cents       INT          NOT NULL DEFAULT 0,
    total_cents     INT          NOT NULL,
    promotion_id    UUID,
    promotion_label VARCHAR(120),
    payment_status  VARCHAR(16)  NOT NULL DEFAULT 'NONE',
    ship_to         TEXT         NOT NULL DEFAULT '',
    tracking_note   TEXT         NOT NULL DEFAULT '',
    placed_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    held_at         TIMESTAMPTZ,
    shipped_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    cancelled_at    TIMESTAMPTZ,
    settled_at      TIMESTAMPTZ
);
CREATE INDEX product_order_buyer_idx  ON economy.product_order (buyer_id, placed_at DESC);
CREATE INDEX product_order_seller_idx ON economy.product_order (seller_id, status, placed_at DESC);
-- The auto-complete sweep reads "shipped and never confirmed" directly.
CREATE INDEX product_order_shipped_idx ON economy.product_order (status, shipped_at)
    WHERE status = 'SHIPPED';

CREATE TABLE economy.product_order_line (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id         UUID         NOT NULL REFERENCES economy.product_order (id) ON DELETE CASCADE,
    product_id       UUID         NOT NULL,
    variant_id       UUID         NOT NULL,
    product_name     VARCHAR(140) NOT NULL,
    variant_label    VARCHAR(120) NOT NULL,
    unit_price_cents BIGINT       NOT NULL,
    quantity         INT          NOT NULL,
    line_total_cents BIGINT       NOT NULL
);
CREATE INDEX product_order_line_order_idx ON economy.product_order_line (order_id);

-- Verified-purchase reviews (SPECS §6, the engagement-table shape). One review
-- per buyer per product — a second purchase edits it rather than stacking a
-- duplicate. The seller's reply is a column, because SPECS caps it at one.
CREATE TABLE economy.review (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID        NOT NULL REFERENCES economy.product (id) ON DELETE CASCADE,
    order_id   UUID        NOT NULL,
    author_id  UUID        NOT NULL,
    rating     INT         NOT NULL CHECK (rating BETWEEN 1 AND 5),
    body       TEXT        NOT NULL DEFAULT '',
    reply_body TEXT,
    replied_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE (product_id, author_id)
);
CREATE INDEX review_product_idx ON economy.review (product_id, created_at DESC);

CREATE TABLE economy.review_photo (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    review_id  UUID NOT NULL REFERENCES economy.review (id) ON DELETE CASCADE,
    sort_order INT  NOT NULL,
    image_url  TEXT NOT NULL
);
CREATE INDEX review_photo_review_idx ON economy.review_photo (review_id);
