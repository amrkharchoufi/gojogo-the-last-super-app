-- Phase 4 · Milestone 6: disputes, and the rest of the phase's breadth
-- (SPECS §5, ARCHITECTURE §10) — the milestone that closes Phase 4.
--
-- The gap that has been open since 2e M3 shipped the wallet, and that every
-- milestone since has carried in its own "not built" list. Cancelling an order
-- before delivery releases the hold; after delivery there was **no route back
-- at all** — the escrow is empty, the money is split three ways, and nothing in
-- this system could move any of it.
--
-- **The shape follows from arguing after the money has moved.** There is no pot
-- to refund from, so a refund is money coming back off somebody who has already
-- been paid, and the only question that can be answered is *which of the
-- three*: the kitchen (food value less commission), the courier (delivery fees
-- and the tip), or the platform (commission and the service fee). Each is
-- capped at what they actually received for this order — not because the ledger
-- would refuse a bigger debit, but because taking one order's dispute out of
-- another order's earnings is how a restaurant discovers a refund it was never
-- shown.
--
-- **And none of them can go below zero.** Only EXTERNAL accounts allow a
-- negative balance (V23), so a merchant who has already paid out cannot fund a
-- refund at all. That is a refusal naming the number rather than a silent
-- fallback to the platform: somebody has to decide who absorbs it, and deciding
-- on their behalf is how the platform ends up paying for every kitchen's
-- mistakes without anybody choosing that.
--
-- **Resolution is a human act**, per §5, and the schema keeps it one: there is
-- a `resolved_by` and there is no rule that could fill it in.

-- ---------------------------------------------------------------------------
-- 1. The report
-- ---------------------------------------------------------------------------
--
-- One per order, which is a unique index rather than a convention. Not one per
-- kitchen — that reads better on a multi-merchant order right up until two
-- operators open the two reports and refund the same missing pizza twice.

CREATE TABLE delivery.dispute (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id        UUID         NOT NULL REFERENCES delivery.customer_order (id) ON DELETE CASCADE,
    -- Which kitchen's bag, when the complaint is about one. NULL for a problem
    -- with the order as a whole — a delivery that never arrived is not any
    -- particular restaurant's fault. A MERCHANT-funded refund requires it.
    sub_order_id    UUID,
    user_id         UUID         NOT NULL,
    reason          VARCHAR(32)  NOT NULL,
    note            TEXT         NOT NULL DEFAULT '',
    state           VARCHAR(24)  NOT NULL DEFAULT 'OPEN',
    -- What the customer says is wrong, priced from the order's own lines at
    -- filing time. A starting point for the operator, never a cap: somebody who
    -- says two of six items are missing may be owed more, and may be owed
    -- nothing.
    claimed_cents   INT          NOT NULL DEFAULT 0,
    refund_cents    INT          NOT NULL DEFAULT 0,
    payer           VARCHAR(16),
    resolution_note TEXT         NOT NULL DEFAULT '',
    resolved_by     VARCHAR(200) NOT NULL DEFAULT '',
    resolved_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    version         INT          NOT NULL DEFAULT 0,
    -- A refund names its payer, and a rejection has neither. Enforced here
    -- because the alternative is a row that says money moved and cannot say
    -- from whom.
    CONSTRAINT dispute_refund_has_a_payer
        CHECK ((state = 'RESOLVED_REFUND' AND payer IS NOT NULL AND refund_cents > 0)
            OR (state <> 'RESOLVED_REFUND' AND refund_cents = 0))
);

CREATE UNIQUE INDEX dispute_one_per_order_idx ON delivery.dispute (order_id);
-- The queue read: open first, oldest first within that.
CREATE INDEX dispute_state_idx ON delivery.dispute (state, created_at);

COMMENT ON TABLE delivery.dispute IS
    'A complaint about a delivered order (Phase 4 M6, SPECS §5). One per order. '
    'Resolution is a human act on /v1/delivery/admin/disputes — nothing '
    'auto-refunds and nothing escalates on a timer.';

COMMENT ON COLUMN delivery.dispute.payer IS
    'MERCHANT | COURIER | PLATFORM — whose earnings on this order the refund '
    'came out of. Settlement already split the money three ways, so this is the '
    'only question a post-delivery refund can answer.';

-- ---------------------------------------------------------------------------
-- 2. What they said was wrong, and what it looked like
-- ---------------------------------------------------------------------------
--
-- The name and unit price are copies, exactly as `order_line` copies them off
-- the menu: a complaint has to keep saying what it was about after the
-- restaurant renames the dish or re-prices it.

CREATE TABLE delivery.dispute_item (
    dispute_id       UUID        NOT NULL REFERENCES delivery.dispute (id) ON DELETE CASCADE,
    menu_item_id     UUID        NOT NULL,
    name             VARCHAR(200) NOT NULL,
    unit_price_cents INT         NOT NULL,
    qty              INT         NOT NULL
);

CREATE INDEX dispute_item_dispute_idx ON delivery.dispute_item (dispute_id);

-- Private object keys, never URLs, and always ones the server minted — the same
-- posture the drop-off proof photo takes, and a folder apart from it because
-- they are evidence in opposite directions.
CREATE TABLE delivery.dispute_photo (
    dispute_id UUID         NOT NULL REFERENCES delivery.dispute (id) ON DELETE CASCADE,
    object_key VARCHAR(400) NOT NULL
);

CREATE INDEX dispute_photo_dispute_idx ON delivery.dispute_photo (dispute_id);

-- ---------------------------------------------------------------------------
-- 3. The rest of Phase 4's breadth
-- ---------------------------------------------------------------------------
--
-- **Ordering for somebody else** (SPECS §5). A name and a phone on the order,
-- and the asymmetry between them is the design: the *name* is what the
-- courier's screen says, because they need to know who to hand a bag to; the
-- *phone* reaches nobody at all. It is on the order so the person who typed it
-- has somewhere to have put it, and so a future SMS can reach a recipient with
-- no account — handing it to whoever happened to accept the job would be
-- disclosing a stranger's number to a stranger.
--
-- Blank means the booker is the recipient, which is every order before this
-- migration and most orders after it. Ignored entirely on a collection: the
-- person walking to the counter is the person holding the code.

ALTER TABLE delivery.customer_order
    ADD COLUMN recipient_name  VARCHAR(80) NOT NULL DEFAULT '',
    ADD COLUMN recipient_phone VARCHAR(32) NOT NULL DEFAULT '',
    -- **The courier rating** (SPECS §5), deferred since Phase 4 M1 and for the
    -- reason M1 gave: a two-star for a cold burger is a judgement on a kitchen,
    -- and passing the *order* rating to dispatch would make a courier's score a
    -- function of restaurants they do not choose. That was never "couriers
    -- should not be rated" — it was that this needs its own question. It goes
    -- to DispatchApi.rate rather than complete, because the job finished at the
    -- doorstep and re-completing it would count the delivery twice.
    ADD COLUMN courier_rating_given INT;

-- **Opening hours** — found while building M5, and the older of the two gaps.
-- SPECS §9's storefront `info` block has advertised "hours" since 2e M4 with
-- nothing behind it, and this vertical has never known whether a kitchen was
-- open: `active` is the owner saying "we are trading", which is a switch
-- somebody has to remember to flip twice a day and therefore a switch nobody
-- flips. The consequences were small until M5 made them not — an order placed
-- after close waits ten minutes to time out, and a booking for three in the
-- morning is accepted and cancelled hours later, at a moment when nobody can do
-- anything with the refund.
--
-- One column, not seven rows: it is always read whole, never queried across
-- merchants, and a child table would be seven joins on every catalog read to
-- answer a question with one answer. `MON=11:00-23:00;TUE=...`, a day absent
-- means closed that day, and **blank means always open** — which is what every
-- restaurant already in the catalog is, and what keeps this migration from
-- closing anybody.
--
-- The timezone is theirs because hours without a zone are hours in the
-- server's, and the server's is UTC, which is nobody's lunchtime.

ALTER TABLE delivery.merchant
    ADD COLUMN opening_hours VARCHAR(400) NOT NULL DEFAULT '',
    ADD COLUMN timezone      VARCHAR(64)  NOT NULL DEFAULT '';

COMMENT ON COLUMN delivery.merchant.opening_hours IS
    'MON=11:00-23:00;TUE=... — blank is always open. A close at or before its '
    'open runs past midnight, which is a normal kitchen rather than an edge '
    'case. Read alongside `active`, never instead of it: that one is "we are '
    'trading at all" and this is "and right now".';

COMMENT ON COLUMN delivery.customer_order.recipient_phone IS
    'Never disclosed to the courier and never rendered on a share link. It '
    'exists so the person who placed the order has somewhere to have put it, '
    'and for a future SMS to a recipient with no account.';

COMMENT ON COLUMN delivery.customer_order.courier_rating_given IS
    'What the customer thought of whoever brought it — separate from `rating`, '
    'which is about the food. Sent to dispatch on the first submission only: '
    'each one folds into the worker''s running mean, so a re-rate would count '
    'twice.';

-- ---------------------------------------------------------------------------
-- 4. Policy knobs (SPECS §5, §14)
-- ---------------------------------------------------------------------------

INSERT INTO platform.config (key, value, note) VALUES
    ('delivery.share.ttl.minutes', '60',
     'Floor on how long a delivery''s public tracking link lives; the actual '
     'life is whatever is left of the ETA plus the grace below. Both err long, '
     'because a link that outlives a short delivery is harmless and one that '
     'dies mid-delivery is the feature not working.'),
    ('delivery.share.grace.minutes', '30',
     'Added to a delivery share link''s remaining ETA.'),
    ('delivery.dispute.window.hours', '24',
     'How long after delivery a problem can be reported. Counted from delivery '
     'and not from placement, which matters now that an order can be placed '
     'days before it arrives. Short because a complaint is argued from evidence '
     'that still exists.'),
    ('delivery.dispute.max.photos', '4',
     'Photos on one report. The upload is free to the client and the bucket is '
     'not, and nothing is proved by the ninth picture.');
