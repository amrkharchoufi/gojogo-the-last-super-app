-- Phase 4 · Milestone 5: scheduled orders, and changing one before a kitchen
-- has seen it (SPECS §5 "Scheduled orders", ARCHITECTURE §10 Phase 4 M4's
-- breadth work).
--
-- M4 predicted the cheap half of this: "a scheduled pickup is the same poller
-- with no pickupLead". That turned out to be true and to be about a fifth of
-- the milestone, because the expensive half is not the timing at all — it is
-- deciding *when the kitchen finds out*, and everything that follows from an
-- order existing for six hours before anybody is asked about it.
--
-- **No new status, for the fifth milestone running.** "Scheduled" is not a
-- stage of an order: CONFIRMED already means "placed, waiting for the
-- restaurant to answer", and that is exactly what a scheduled order is. The
-- only difference is whether the restaurant has been asked yet, which is a
-- timestamp (`queued_at`) and not a word every client in the field would have
-- to learn.
--
-- **The money is held at checkout, exactly as it always was.** The tempting
-- alternative is to hold at promotion, so a customer's balance is not tied up
-- for six hours — and its failure mode is that the hold fails at 19:10 for a
-- 20:00 dinner, which is the moment nothing can be done about it. Money
-- reserved early is the price of a promise; a promise that can quietly fail is
-- not one.
--
-- **The kitchen is told at promotion, not at placement.** `OrderPlaced` is
-- published when the order enters the queue, which is the one event-ordering
-- change here and falls out of what that event is for: it exists to put an
-- order in front of a person, and a push at noon about an eight o'clock dinner
-- is a push somebody will have forgotten by the time it matters.

-- ---------------------------------------------------------------------------
-- 1. When it is wanted, and when the kitchens find out
-- ---------------------------------------------------------------------------

ALTER TABLE delivery.customer_order
    -- When the customer asked for it: at the door for a delivery, on the
    -- counter for a collection. NULL is an ordinary order, which is every row
    -- that existed before this migration and most rows after it.
    ADD COLUMN scheduled_for TIMESTAMPTZ,
    -- When it should be put in front of the kitchens: scheduled_for minus the
    -- slowest kitchen's own advertised time minus the window they get to
    -- answer in. Computed once, at placement, rather than on every poll — a
    -- merchant editing their ETA must not move an order that has already been
    -- promised to somebody, and a stored column is what the poller's partial
    -- index is on.
    ADD COLUMN queue_at      TIMESTAMPTZ,
    -- When they actually did. NULL means "no kitchen has seen this yet",
    -- which is the whole of what makes an order still changeable: there is no
    -- preparation to be before.
    ADD COLUMN queued_at     TIMESTAMPTZ,
    -- Bumped by every change. The wallet's idempotency keys carry it, so
    -- adjusting a hold twice is two movements and a retried adjustment is one.
    ADD COLUMN revision      INT NOT NULL DEFAULT 0;

-- Every order that already exists was in front of its kitchen from the moment
-- it was placed. Backfilled rather than defaulted, because the column has to
-- be NULL-able for the orders this milestone introduces and a default would
-- put a lie on those.
UPDATE delivery.customer_order SET queued_at = placed_at WHERE queued_at IS NULL;

COMMENT ON COLUMN delivery.customer_order.scheduled_for IS
    'When the customer asked for the food (at the door for a delivery, on the '
    'counter for a collection). NULL for an ordinary order. Never a status: a '
    'scheduled order is CONFIRMED like any other, and what differs is only '
    'whether its kitchens have been asked yet.';

COMMENT ON COLUMN delivery.customer_order.queued_at IS
    'When this order entered its kitchens'' queues — placement for an ordinary '
    'order, promotion for a scheduled one. NULL means no kitchen has seen it, '
    'which is what makes the order still changeable and what stops the accept '
    'timeout counting against a restaurant nobody has asked yet.';

-- The poller's whole query. Partial, because the rows it wants are the small
-- minority that are waiting: an index over every order ever placed to find the
-- four due in the next minute is an index paying for a scan nobody asked for.
CREATE INDEX customer_order_due_for_queue_idx
    ON delivery.customer_order (queue_at)
    WHERE queued_at IS NULL;

-- ---------------------------------------------------------------------------
-- 2. Policy knobs (SPECS §5, §14)
-- ---------------------------------------------------------------------------

INSERT INTO platform.config (key, value, note) VALUES
    ('delivery.schedule.min.lead.minutes', '45',
     'How far ahead a scheduled order must be. A floor rather than the whole '
     'rule: the real minimum is this or the slowest kitchen''s own advertised '
     'time plus the window they get to answer in, whichever is later, and the '
     'refusal names the earliest time that would work.'),
    ('delivery.schedule.max.days', '7',
     'How far ahead an order may be scheduled. A cap on how long the '
     'customer''s money sits in escrow as much as on the calendar.'),
    ('delivery.order.max.scheduled', '5',
     'How many scheduled orders one customer may have waiting. Each one holds '
     'its own money, so the wallet is the real limit — this is the one that '
     'stops a mistake being unbounded.');
