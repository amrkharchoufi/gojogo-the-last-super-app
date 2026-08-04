-- Phase 4 · Milestone 3: multi-merchant orders (SPECS §5 "Multi-merchant
-- orders", ARCHITECTURE §10 Phase 4 M3).
--
-- One checkout, one payment hold, and a kitchen's worth of work per merchant.
-- The order becomes the parent — payment, address, courier, totals — and a new
-- sub_order per merchant carries what is actually one restaurant's business:
-- their basket, their prep estimate, their pickup code, their share of the
-- money. The parent keeps the six statuses and the courier keeps being one
-- person; what changes is that CONFIRMED / PREPARING now summarise several
-- kitchens instead of describing one.
--
-- **The pickup code moves down to the sub-order**, exactly as SPECS §5 said it
-- would: M2 put it on the order because there was exactly one merchant, and a
-- courier collecting three bags now proves each counter separately — one code
-- per kitchen, typed where that kitchen's screen is showing it.
--
-- **Courier states stay on the parent (single-courier default).** The per-leg
-- split — several couriers for one order when the route is expensive — is
-- deliberately not built; what makes that honest is the cap: an order may name
-- at most CONFIG 3 merchants, which is a basket one person can carry.
--
-- **Cancellation becomes per-sub-order until its merchant accepts.** A partial
-- release moves exactly that merchant's slice (subtotal − discount + their
-- delivery fee) back out of escrow, and released_cents on the parent records
-- the running total so settlement can insist that what it splits plus what was
-- given back equals what was held. The service fee and the tip are the whole
-- order's and only move at the end, whichever end that is.
--
-- **Every existing order becomes a single-sub-order parent.** The backfill
-- copies the per-merchant fields down verbatim — including the pickup code, so
-- an order in flight during this deploy is collected with the same digits the
-- kitchen's screen was already showing. Nothing about a live order changes
-- shape from any participant's point of view.

-- ---------------------------------------------------------------------------
-- 1. The sub-order: one merchant's slice of one order
-- ---------------------------------------------------------------------------

CREATE TABLE delivery.sub_order (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id           UUID         NOT NULL REFERENCES delivery.customer_order (id) ON DELETE CASCADE,
    merchant_id        UUID         NOT NULL REFERENCES delivery.merchant (id),
    -- CONFIRMED → PREPARING → COLLECTED → DELIVERED, or CANCELLED: the order's
    -- own states minus the courier ones, which live on the parent. COLLECTED is
    -- the one word of its own — "this kitchen's bag is in the courier's hand"
    -- is a fact about one merchant, not about the order.
    status             VARCHAR(32)  NOT NULL DEFAULT 'CONFIRMED',
    subtotal_cents     INT          NOT NULL DEFAULT 0,
    -- This merchant's advertised delivery fee. The courier makes one stop per
    -- merchant and is paid every fee; a cancelled sub-order takes its fee back
    -- with it.
    delivery_fee_cents INT          NOT NULL DEFAULT 0,
    discount_cents     INT          NOT NULL DEFAULT 0,
    -- A promotion is a merchant's own campaign, so it attaches to their slice.
    promotion_id       UUID,
    promotion_code     VARCHAR(32)  NOT NULL DEFAULT '',
    -- The six digits this kitchen's screen shows and the courier types at this
    -- counter and no other. Blank means "no check to run" (pre-V38 orders).
    pickup_code        VARCHAR(8)   NOT NULL DEFAULT '',
    prep_minutes       INT,
    accepted_at        TIMESTAMPTZ,
    ready_at           TIMESTAMPTZ,
    collected_at       TIMESTAMPTZ,
    cancel_reason      VARCHAR(240) NOT NULL DEFAULT '',
    sort_order         INT          NOT NULL DEFAULT 0,
    version            INT          NOT NULL DEFAULT 0
);

-- The kitchen's queue, and the parent's own reads.
CREATE INDEX sub_order_merchant_idx ON delivery.sub_order (merchant_id, status);
CREATE INDEX sub_order_order_idx    ON delivery.sub_order (order_id, sort_order);

-- Lines belong to a merchant's slice now. The parent reference stays — a
-- receipt is still read flat — and the sub-order id says whose bag a line is in.
ALTER TABLE delivery.order_line ADD COLUMN sub_order_id UUID;

-- What has already been given back out of the hold, in cents. Settlement
-- refuses unless splits + released = held, which is the same arithmetic check
-- the single-merchant order had, taught about partial refunds.
ALTER TABLE delivery.customer_order ADD COLUMN released_cents INT NOT NULL DEFAULT 0;

-- ---------------------------------------------------------------------------
-- 2. Backfill: every order that exists is a single-sub-order parent
-- ---------------------------------------------------------------------------

INSERT INTO delivery.sub_order (order_id, merchant_id, status, subtotal_cents,
                                delivery_fee_cents, discount_cents, promotion_id,
                                promotion_code, pickup_code, prep_minutes,
                                accepted_at, ready_at, collected_at, cancel_reason,
                                sort_order)
SELECT o.id, o.merchant_id,
       CASE o.status
           WHEN 'CONFIRMED'             THEN 'CONFIRMED'
           WHEN 'PREPARING'             THEN 'PREPARING'
           WHEN 'COURIER_TO_RESTAURANT' THEN 'PREPARING'
           WHEN 'DELIVERING'            THEN 'COLLECTED'
           WHEN 'DELIVERED'             THEN 'DELIVERED'
           ELSE 'CANCELLED'
       END,
       o.subtotal_cents, o.delivery_fee_cents, o.discount_cents, o.promotion_id,
       o.promotion_code, o.pickup_code, o.prep_minutes,
       o.accepted_at, o.ready_at, o.picked_up_at, o.cancel_reason, 0
FROM delivery.customer_order o;

UPDATE delivery.order_line l
SET sub_order_id = s.id
FROM delivery.sub_order s
WHERE s.order_id = l.order_id;

ALTER TABLE delivery.order_line ALTER COLUMN sub_order_id SET NOT NULL;

-- ---------------------------------------------------------------------------
-- 3. The parent sheds what moved down
-- ---------------------------------------------------------------------------
--
-- merchant_id, the prep fields, the pickup code and the promotion now live on
-- the sub-order and nowhere else. Keeping copies on the parent would be a
-- second source of truth that is right exactly as long as every order has one
-- merchant — i.e. wrong from the first real use of this milestone. What stays
-- up here is genuinely the order's: the courier, the address, the money totals,
-- the delivery PIN (one door), ready_at as "when the *last* kitchen is done" —
-- which is what the courier search and the customer's countdown are timed from.

ALTER TABLE delivery.customer_order
    DROP COLUMN merchant_id,
    DROP COLUMN accepted_at,
    DROP COLUMN prep_minutes,
    DROP COLUMN pickup_code,
    DROP COLUMN promotion_id,
    DROP COLUMN promotion_code;

COMMENT ON COLUMN delivery.customer_order.ready_at IS
    'When the food is expected to be ready across every kitchen still cooking '
    '— the latest accepted sub-order''s ready_at. The courier search starts at '
    'this minus the pickup lead, because a courier who arrives before the '
    'slowest kitchen is done waits unpaid at a counter.';

COMMENT ON COLUMN delivery.customer_order.released_cents IS
    'Running total already released back to the customer by per-sub-order '
    'cancellations. Settlement splits must sum to total_cents minus this, or '
    'nothing settles.';

COMMENT ON TABLE delivery.sub_order IS
    'One merchant''s slice of a customer_order (Phase 4 M3): their basket, '
    'their prep clock, their pickup code, their share of the money. The parent '
    'keeps the courier and the six statuses; a sub-order is cancellable on its '
    'own until its merchant accepts.';

-- ---------------------------------------------------------------------------
-- 4. Policy knob (SPECS §5, §14)
-- ---------------------------------------------------------------------------

INSERT INTO platform.config (key, value, note) VALUES
    ('delivery.order.max.merchants', '3',
     'Most merchants one order may span. One courier collects every bag '
     '(single-courier default, SPECS §5); the per-leg multi-courier split is '
     'not built, and this cap is what keeps that honest — three counters is a '
     'trip one person makes, five is a relay.');
