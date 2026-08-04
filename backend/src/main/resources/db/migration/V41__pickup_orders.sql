-- Phase 4 · Milestone 4: pickup / collect-in-store (SPECS §5 "Pickup /
-- collect-in-store", ARCHITECTURE §10 Phase 4 M4).
--
-- The gap found on 2026-07-31: the vision, the plan and §9's storefront `info`
-- block all assumed collection existed, and none of them defined it. It is a
-- fulfilment KIND on the order — not a delivery with a zero courier, which is
-- the modelling mistake that would put a nobody-shaped courier into every
-- screen, every event and every settlement in this vertical.
--
-- **What a pickup order does not have.** No dispatch request and no courier
-- (so no COURIER_TO_RESTAURANT and no DELIVERING — the six statuses stay, and
-- a collect order simply never visits two of them). No delivery fee and no
-- tip, so the split is food − commission to the merchant and commission +
-- service fee to the platform: exactly the arithmetic settlement already does
-- with the courier's two lines at zero, which the ledger skips as "a zero fee
-- is not an entry". And no delivery address, because the address of a pickup
-- is the counter.
--
-- **The code inverts rather than multiplying.** Collection is the same handoff
-- code M2 built and M3 moved down to the sub-order — shown to the *customer*
-- and typed by the *merchant*, which is the direction SPECS §5 asked for and
-- the opposite of the courier's. The rule underneath both is one rule: the
-- code is always displayed to the party that does not type it, and typed by
-- the party who is paid for completing the step. For a delivery that is the
-- courier; for a collection it is the kitchen holding the bag.
--
-- **Readiness becomes a fact, not just an estimate.** A delivery's readiness
-- is a time the courier is timed against; a collection's readiness is a
-- message to a person who has to put their shoes on. `ready_marked_at` is the
-- moment a kitchen actually said so, kept beside the estimate rather than
-- overwriting it — still a timestamp and still not a status, which is the
-- decision M1 made about "the food is ready" and this milestone had no reason
-- to reopen.

-- ---------------------------------------------------------------------------
-- 1. The order's kind
-- ---------------------------------------------------------------------------
--
-- On the order and not on the sub-order, and that is the one place this
-- milestone departs from what the plan predicted. A per-merchant kind reads
-- well until the money is followed: a mixed order needs a courier for some
-- bags and not others, a delivery fee on some slices and not others, and then
-- has to decide whether the parent is finished when the courier is done or
-- when the customer eventually walks to the other counter — with one hold,
-- one settlement and one terminal moment to spend on the question. A checkout
-- is one kind; a customer who wants both places two orders, and is told so.

ALTER TABLE delivery.customer_order
    ADD COLUMN fulfilment_kind VARCHAR(16) NOT NULL DEFAULT 'DELIVERY';

COMMENT ON COLUMN delivery.customer_order.fulfilment_kind IS
    'DELIVERY | PICKUP. A PICKUP order has no courier, no dispatch request, no '
    'delivery fee and no tip, and its address is the counter it is collected '
    'from. Every order that existed before Phase 4 M4 is a DELIVERY, which is '
    'what the column default says and what the backfill relies on.';

-- ---------------------------------------------------------------------------
-- 2. What a merchant offers
-- ---------------------------------------------------------------------------
--
-- Off by default: collection is a thing a restaurant has to have a counter and
-- a person for, and defaulting it on would advertise a service on behalf of
-- every merchant already in the catalog. `active = false` closes a restaurant
-- for both — "open" is one switch about whether the kitchen is cooking, and a
-- second switch would eventually disagree with the first.

ALTER TABLE delivery.merchant
    ADD COLUMN pickup_enabled      BOOLEAN      NOT NULL DEFAULT FALSE,
    -- Null means "the same as delivery": collection is usually quicker (no
    -- courier to wait for), but a kitchen that has not said so is not one this
    -- column should invent a faster number for.
    ADD COLUMN pickup_prep_minutes INT,
    -- Where to walk to, when that is not simply the restaurant's own address —
    -- "side door on Rue Ali", a mall unit number. Blank falls back to the
    -- merchant's name and map pin, which every client already draws.
    ADD COLUMN pickup_address      VARCHAR(200) NOT NULL DEFAULT '';

COMMENT ON COLUMN delivery.merchant.pickup_enabled IS
    'Whether this restaurant lets customers collect in store. Off by default; '
    'independent of delivery, but subordinate to active — a closed restaurant '
    'is closed for both.';

-- ---------------------------------------------------------------------------
-- 3. The slice's own pickup facts
-- ---------------------------------------------------------------------------

ALTER TABLE delivery.sub_order
    -- Copied at placement, like the delivery address on the parent: a receipt
    -- says where the food was collected from even after the merchant edits
    -- their own row.
    ADD COLUMN pickup_address  VARCHAR(200) NOT NULL DEFAULT '',
    -- When the kitchen actually tapped "ready", as opposed to when they
    -- guessed it would be. The customer's "it's ready, come and get it" push
    -- is this, and nothing else can be: ready_at is an estimate right up until
    -- the moment it is a fact.
    ADD COLUMN ready_marked_at TIMESTAMPTZ;

COMMENT ON COLUMN delivery.sub_order.ready_marked_at IS
    'When this kitchen said the food is actually ready (Phase 4 M4). Distinct '
    'from ready_at, which is an estimate until this is set. Drives the '
    'READY_FOR_PICKUP push and the collect affordance; still a timestamp '
    'rather than a status, per the Phase 4 M1 decision about readiness.';

-- ---------------------------------------------------------------------------
-- 4. Policy knobs (SPECS §5, §14)
-- ---------------------------------------------------------------------------

INSERT INTO platform.config (key, value, note) VALUES
    ('delivery.pickup.prep.default.minutes', '15',
     'Prep estimate for a collection when the kitchen accepts without naming '
     'one and has set no pickup_prep_minutes of their own. Shorter than the '
     'delivery default because nobody is waiting on a courier.');
