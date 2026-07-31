-- Delivery checkout: an order that is actually paid for (SPECS.md §1, §6).
--
-- Since 2b M4 a delivery order has been priced by the server and then placed
-- with no payment step at all — the one thing a commerce vertical cannot
-- ship without. The wallet (V23) is what it was waiting for.
--
-- Money is held, not taken, at placement: the customer's funds move to their own
-- ESCROW bucket and stay theirs until the food arrives. That is what makes
-- cancellation a release rather than a refund, and it is the same shape a
-- marketplace sale and a service booking will use.
--
-- Two additions arrive with it, because a checkout is where they land:
-- **tips** (SPECS §1 — courier keeps 100%) and **promotions** (SPECS §6 — a
-- discount is an order line, so a receipt still adds up and a refund knows
-- what was actually paid).

-- Legacy orders keep working: everything below defaults to "no money involved",
-- which is exactly what an order placed before this migration was. UNPAID is a
-- real state, not a null — an order from last week is not half-paid.
ALTER TABLE delivery.customer_order
    ADD COLUMN tip_cents      INT          NOT NULL DEFAULT 0,
    ADD COLUMN discount_cents INT          NOT NULL DEFAULT 0,
    ADD COLUMN promotion_id   UUID,
    -- Copied, not looked up — the same reasoning as the address copy above it:
    -- a receipt must keep saying WELCOME10 after the promotion is deleted.
    ADD COLUMN promotion_code VARCHAR(32)  NOT NULL DEFAULT '',
    ADD COLUMN payment_status VARCHAR(16)  NOT NULL DEFAULT 'UNPAID',
    ADD COLUMN paid_at        TIMESTAMPTZ,
    ADD COLUMN settled_at     TIMESTAMPTZ,

    CONSTRAINT customer_order_payment_status_chk
        CHECK (payment_status IN ('UNPAID', 'HELD', 'CAPTURED', 'RELEASED', 'REFUNDED')),
    CONSTRAINT customer_order_tip_chk CHECK (tip_cents >= 0),
    CONSTRAINT customer_order_discount_chk CHECK (discount_cents >= 0);

-- Promotions (SPECS §6's shared shape, delivery first). Authored by the
-- merchant on their own /mine surface; applied server-side at pricing time,
-- because a discount the client computed is a discount the client chose.
CREATE TABLE delivery.promotion (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Whose promotion this is. Null would mean platform-wide; nothing creates
    -- one yet, so it is NOT NULL until something does — a nullable column with
    -- no writer is a guess about the future.
    merchant_id        UUID         NOT NULL,

    -- Null code = automatic: applies to every basket that qualifies, with no
    -- typing. A code is uppercased on write so `welcome10` and `WELCOME10` are
    -- the same promotion rather than two.
    code               VARCHAR(32),
    label              VARCHAR(80)  NOT NULL DEFAULT '',

    kind               VARCHAR(16)  NOT NULL,
    -- PERCENT reads value_bps, FIXED reads amount_cents, FREE_DELIVERY reads
    -- neither — it discounts whatever this merchant's delivery fee happens to
    -- be on the day, which is why it is a kind and not a fixed amount.
    value_bps          INT          NOT NULL DEFAULT 0,
    amount_cents       INT          NOT NULL DEFAULT 0,

    min_basket_cents   INT          NOT NULL DEFAULT 0,
    -- 0 = uncapped. A percentage promotion without a cap is how a merchant
    -- accidentally gives away $80 on one large order.
    max_discount_cents INT          NOT NULL DEFAULT 0,
    -- 0 = unlimited. Counted from promotion_redemption below.
    per_user_limit     INT          NOT NULL DEFAULT 0,

    starts_at          TIMESTAMPTZ,
    ends_at            TIMESTAMPTZ,
    active             BOOLEAN      NOT NULL DEFAULT true,

    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT promotion_kind_chk CHECK (kind IN ('PERCENT', 'FIXED', 'FREE_DELIVERY')),
    CONSTRAINT promotion_bps_chk CHECK (value_bps BETWEEN 0 AND 10000),
    CONSTRAINT promotion_amount_chk CHECK (amount_cents >= 0),
    CONSTRAINT promotion_window_chk CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at)
);

-- One live code per merchant. Two promotions answering to WELCOME10 is a
-- question with no right answer, so the database refuses it rather than the
-- pricing code picking a winner.
CREATE UNIQUE INDEX promotion_code_idx
    ON delivery.promotion (merchant_id, upper(code))
    WHERE code IS NOT NULL AND active;

CREATE INDEX promotion_merchant_idx ON delivery.promotion (merchant_id, created_at DESC);

-- What was actually used, by whom. Exists for the per-user limit, and doubles
-- as the answer to "did this campaign do anything".
CREATE TABLE delivery.promotion_redemption (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    promotion_id UUID        NOT NULL REFERENCES delivery.promotion (id) ON DELETE CASCADE,
    user_id      UUID        NOT NULL,
    -- One redemption per order, enforced below: a retried checkout must not
    -- count twice against the limit.
    order_id     UUID        NOT NULL,
    amount_cents INT         NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX promotion_redemption_order_idx
    ON delivery.promotion_redemption (order_id);
CREATE INDEX promotion_redemption_user_idx
    ON delivery.promotion_redemption (promotion_id, user_id);
