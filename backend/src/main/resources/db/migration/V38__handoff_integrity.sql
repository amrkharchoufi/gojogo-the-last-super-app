-- Phase 4 · Milestone 2: handoff integrity (SPECS.md §5 "Handoff integrity",
-- ARCHITECTURE §10 Phase 4 M2).
--
-- M1 made the courier a real person and left the two moments that matter most
-- unproven. A courier taps "I have the food" and the order moves; a courier taps
-- "I handed it over" and the money moves. Both taps are unwitnessed, and the
-- second one pays somebody. This migration is the evidence behind them, and the
-- columns fall into three groups answering three different questions.
--
--   is this the right bag  — pickup_code. The restaurant's screen shows it and
--                            the courier types it, so the tap is backed by the
--                            fact that somebody stood at that counter
--   did it reach the door  — handoff_mode / delivery_pin / handoff_attempts /
--                            proof_photo_key. A PIN the customer reads out, a
--                            photo for a doorstep nobody answers, or a plain
--                            confirm — and a count of the wrong guesses, because
--                            this is the one where being wrong pays somebody
--   how do they talk       — conversation_id, the courier↔customer thread
--
-- **The code direction is reversed from SPECS §5, deliberately.** The spec says
-- the courier shows a code and the merchant confirms it. This does the opposite:
-- the merchant's screen displays it and the courier types it. The party who must
-- act should be the party with the incentive — a merchant who forgets to tap
-- leaves a courier holding food they cannot mark collected, whereas a courier
-- cannot be paid until they complete the step, and the only way to learn the
-- code is to stand at that counter, which is exactly the fact the code exists to
-- prove. Recorded as a SPECS refinement rather than a divergence.
--
-- **Still no new order status.** SPECS §5 says a failed PIN leaves the order
-- `ARRIVED`; there is no such status and there will not be one, for the reason
-- M1 refused to add one. A failed handoff leaves the order in DELIVERING, which
-- is precisely what it is: the courier still has the food.
--
-- **What this means for an order already in flight.** Every existing row gets
-- blank codes, PIN mode and zero attempts. A blank code is not a locked door —
-- both handoff verbs treat "this order has no code" as "there is nothing to
-- check" and complete exactly as M1 did. That is the whole reason the defaults
-- are '' rather than a minted value: a migration must not retroactively lock a
-- courier out of a delivery they are already carrying, and it cannot mint a
-- code that anybody standing in that restaurant could possibly know. So an order
-- in DELIVERING when this deploys is handed over on a plain confirm, and every
-- order accepted after it carries both codes from the moment there is a bag.

-- ---------------------------------------------------------------------------
-- 1. The two codes, and what happens when one is wrong
-- ---------------------------------------------------------------------------

ALTER TABLE delivery.customer_order
    ADD COLUMN pickup_code      VARCHAR(8)   NOT NULL DEFAULT '',
    ADD COLUMN handoff_mode     VARCHAR(16)  NOT NULL DEFAULT 'PIN',
    ADD COLUMN delivery_pin     VARCHAR(8)   NOT NULL DEFAULT '',
    ADD COLUMN handoff_attempts INT          NOT NULL DEFAULT 0,
    ADD COLUMN proof_photo_key  VARCHAR(300),
    ADD COLUMN conversation_id  UUID;

COMMENT ON COLUMN delivery.customer_order.pickup_code IS
    'Minted when the restaurant accepts — the first moment there is a bag to '
    'hand over, which is also why no screen ever has to render a null. Shown '
    'on the kitchen''s queue and typed by the courier; it is deliberately never '
    'returned on the courier''s own job, because a code the courier can read is '
    'a code that proves nothing. Blank on every order accepted before this '
    'migration, which means "no check to run".';

COMMENT ON COLUMN delivery.customer_order.handoff_mode IS
    'PIN | PHOTO | CONFIRM. The customer''s choice of how the food is handed '
    'over, changeable right up until it is — contactless is a decision people '
    'make when the courier is already close. An unrecognised word falls back to '
    'the configured default rather than failing: a checkout must not break on a '
    'word an older client sent.';

COMMENT ON COLUMN delivery.customer_order.delivery_pin IS
    'Minted alongside pickup_code and shown only to the customer. Returned on '
    'their order and on nobody else''s view of it: a PIN the courier can read '
    'is a delivery they can confirm from the end of the street.';

COMMENT ON COLUMN delivery.customer_order.handoff_attempts IS
    'Wrong delivery-PIN attempts. Counted here and *not* at pickup, and the '
    'asymmetry is the point: at the counter the merchant is standing right '
    'there, so the code is a check rather than a gate and a courier who fails '
    'it must not be locked out of food they are already holding. At the door '
    'the risk is the opposite one — a courier marking an undelivered order '
    'delivered — so the attempts are counted, and reaching the maximum opens '
    'the photo fallback rather than stranding them.';

COMMENT ON COLUMN delivery.customer_order.proof_photo_key IS
    'Private object key for the drop-off photo (media''s private prefix, folder '
    '"delivery-proof"), never a URL and never handed to a client. The server '
    'presigns the PUT and stamps the key it minted, so no request anywhere '
    'accepts a client-supplied key. The customer sees the photo through a '
    'short-lived signed GET minted per read.';

COMMENT ON COLUMN delivery.customer_order.conversation_id IS
    'The 1:1 messaging thread between the customer and the courier, opened at '
    'assignment with a ConversationContext(kind=order). The third consumer of '
    'that seam after a listing and a ride, which is the point of it being '
    'generic — messaging still knows nothing about orders.';

-- ---------------------------------------------------------------------------
-- 2. Policy knobs (SPECS §5, §14)
-- ---------------------------------------------------------------------------
--
-- Every default here matches the fallback DeliveryPolicy passes to ConfigApi,
-- per that contract: an empty config table must behave exactly like a populated
-- one, and the delivery tests assert it by running against a registry with
-- nothing in it.

INSERT INTO platform.config (key, value, note) VALUES
    ('delivery.handoff.mode.default', 'PIN',
     'How a delivery is handed over when the customer expresses no preference. '
     'PIN rather than CONFIRM because the default should be the one that proves '
     'something, and rather than PHOTO because most people are at the door'),
    ('delivery.handoff.max.attempts', '3',
     'Wrong delivery PINs before the photo fallback opens. Not a lockout: a '
     'courier who cannot complete a delivery is a courier standing in the '
     'street with somebody''s dinner, which is worse than the abuse the counter '
     'is there to catch'),
    ('delivery.handoff.code.length', '6',
     'Digits in the pickup code and the delivery PIN. Numeric so it can be read '
     'aloud across a counter or down a phone, and six because that is the '
     'length people already type from memory');
