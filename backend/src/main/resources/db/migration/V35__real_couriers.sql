-- Phase 4 · Milestone 1: real couriers (SPECS.md §3 "Courier trigger for orders",
-- §5, ARCHITECTURE §10 Phase 4 M1).
--
-- The swap 2b M4 was explicitly designed for. Until now every delivery order
-- was walked along a *simulated timeline* by `OrderFulfilmentJob`: a kitchen
-- that always took twenty seconds and a courier picked from a hardcoded roster
-- of four names. The state machine, the events and the API were the real thing;
-- only the actors were fake. This migration is what replaces them, and the
-- columns fall into three groups that answer three different questions.
--
--   who is carrying it   — courier_worker_id / courier_user_id, the dispatch
--                          registration and the profile behind it, which is what
--                          turns "Yassine B., 4.94" from a constant into a person
--                          who gets paid
--   when things happened — accepted_at / prep_minutes / ready_at / picked_up_at.
--                          The timeline used to be derived from placed_at alone,
--                          because there was nothing else to derive it from. A
--                          real kitchen says how long it needs, and that estimate
--                          is what schedules the courier search
--   why it is stuck      — courier_search / cancel_reason. A simulation never
--                          failed; a real one does, and "nobody accepted" and
--                          "the restaurant said no" are different things to be
--                          told
--
-- Deliberately *no new order status*. CONFIRMED → PREPARING →
-- COURIER_TO_RESTAURANT → DELIVERING → DELIVERED → CANCELLED is unchanged, and
-- that is the point of the swap: the client, the events and the notification
-- matrix carry on reading the same six words. "The food is ready and no courier
-- has been found yet" is a *timestamp* (ready_at with courier_search = FAILED),
-- not a seventh state — it is not a stage of an order, it is a problem with one.

-- ---------------------------------------------------------------------------
-- 1. The order learns who is carrying it and when things actually happened
-- ---------------------------------------------------------------------------

ALTER TABLE delivery.customer_order
    ADD COLUMN accepted_at       TIMESTAMPTZ,
    ADD COLUMN prep_minutes      INT,
    ADD COLUMN ready_at          TIMESTAMPTZ,
    ADD COLUMN picked_up_at      TIMESTAMPTZ,
    ADD COLUMN courier_worker_id UUID,
    ADD COLUMN courier_user_id   UUID,
    ADD COLUMN courier_search    VARCHAR(16)  NOT NULL DEFAULT 'NONE',
    ADD COLUMN cancel_reason     VARCHAR(240) NOT NULL DEFAULT '';

COMMENT ON COLUMN delivery.customer_order.courier_worker_id IS
    'The dispatch.worker registration carrying this order. No foreign key: '
    'dispatch is another module''s schema (ARCHITECTURE §4), and the id is '
    'handed over on an Assignment rather than read across.';

COMMENT ON COLUMN delivery.customer_order.courier_user_id IS
    'The profile behind that registration — who the delivery fee and the tip '
    'are paid to at settlement, and whose name the customer sees.';

COMMENT ON COLUMN delivery.customer_order.ready_at IS
    'When the kitchen expects to be done: accepted_at + prep_minutes. The '
    'courier search is scheduled for ready_at minus the pickup lead, which is '
    'SPECS §3''s "approaching readiness" trigger and the whole reason a '
    'DispatchRequest carries startAfter.';

COMMENT ON COLUMN delivery.customer_order.courier_search IS
    'NONE | SEARCHING | ASSIGNED | FAILED. FAILED is the state a simulation '
    'could never reach: dispatch asked everybody within range and nobody took '
    'it. The order does not cancel itself over that — the food may already be '
    'cooked — it says so, and the customer may still cancel for a full release.';

-- The merchant's queue: every live order for one restaurant, oldest first.
CREATE INDEX customer_order_merchant_idx
    ON delivery.customer_order (merchant_id, status, placed_at);

-- The courier's own job, and their delivery history. Partial, because the
-- overwhelming majority of rows in this table never had a courier.
CREATE INDEX customer_order_courier_idx
    ON delivery.customer_order (courier_user_id, status_changed_at DESC)
    WHERE courier_user_id IS NOT NULL;

-- Nothing is done here about orders that are in flight when this deploys, and
-- that is deliberate. Such an order would otherwise be stranded — the job that
-- moved it no longer exists, so it would sit non-terminal forever, holding the
-- customer's money in escrow and their one live-order slot with it. Cancelling
-- them in SQL is the wrong fix: releasing an escrow hold is a ledger movement
-- and belongs to `payments`, and a row marked CANCELLED with the money still
-- held is the one genuinely unacceptable outcome. `OrderTimeoutJob` picks them
-- up instead — a non-terminal order with no `accepted_at` older than the accept
-- timeout is exactly what a stranded one looks like, and it is cancelled *and*
-- released through the same path a restaurant that never answers takes.

-- ---------------------------------------------------------------------------
-- 3. Policy knobs (SPECS §3, §5, §14)
-- ---------------------------------------------------------------------------

-- Seeded by V29 for a dispatch module that turned out not to be the right owner:
-- the lead time is used by whoever computes `startAfter`, and that is the
-- vertical that knows when a kitchen will be done. Nothing has ever read it.
DELETE FROM platform.config WHERE key = 'dispatch.pickup.lead.seconds';

INSERT INTO platform.config (key, value, note) VALUES
    ('delivery.courier.pickup.lead.seconds', '420',
     'How long before the food is ready the courier search starts (SPECS §3, 7 '
     'min). Too early and a courier waits at the counter unpaid; too late and '
     'the food does'),
    ('delivery.prep.default.minutes', '20',
     'Prep estimate used when a restaurant accepts an order without giving one. '
     'A default rather than a required field: an accept that can fail validation '
     'is an accept somebody in a kitchen does not make'),
    ('delivery.prep.max.minutes', '180',
     'The longest prep time a restaurant may claim. A typo of 200 for 20 would '
     'hold a customer''s money for three hours and schedule a courier for '
     'tomorrow'),
    ('delivery.merchant.accept.timeout.minutes', '10',
     'How long an order waits for a restaurant that never answers before it is '
     'cancelled and the money released. Under the simulation nothing had to '
     'answer, so nothing could fail to'),
    ('delivery.dropoff.minutes', '15',
     'Ready-to-door estimate, added to ready_at for the customer''s countdown. '
     'A flat number until dispatch has a routing authority (SPECS §3 — Mapbox '
     'Directions is not built)'),
    ('delivery.courier.categories', 'BIKE,SCOOTER,CAR',
     'Which vehicle categories may be offered a delivery. A comma-separated set '
     'rather than one value, because a basket that fits on a bike also fits in a '
     'car and a city with no bikes on a Tuesday should still get its dinner');
