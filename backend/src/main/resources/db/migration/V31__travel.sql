-- Phase 3 · Milestone 3: the ride loop (SPECS.md §2).
--
-- The first thing in this system that actually publishes a job for dispatch to
-- fill. M1 built the matching and M2 built the drivers; until now nothing has
-- ever asked either of them for anything.
--
-- What makes `travel` different from `delivery` is one word in the vision:
-- **negotiation**. A delivery order has a price the server computed and the
-- customer paid. A ride has a price the two people agree on — the app suggests
-- one, the rider may offer another, and a driver may counter. That is why the
-- fare lives on the ride and the offers are rows, and why dispatch (which knows
-- nothing about money) cannot own this part.

CREATE SCHEMA IF NOT EXISTS travel;

-- ---------------------------------------------------------------------------
-- 1. What a ride costs before anybody argues about it
-- ---------------------------------------------------------------------------
--
-- A table rather than config keys because the shape is per-category and
-- effective-dated, which is three columns of structure the flat key/value
-- registry would have to encode into key names. The registry still owns the
-- *policy* knobs around it (negotiation rounds, TTLs, the cancel fee).
--
-- Money is integer minor units, like everywhere else in this system. There is no
-- decimal arithmetic anywhere near a fare.

CREATE TABLE travel.pricing_config (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- A com.gojogo.dispatch.VehicleCategory name: the rider picks the same
    -- vocabulary dispatch matches on, so "I want an XL" and "who can do an XL"
    -- cannot drift apart.
    category          VARCHAR(16) NOT NULL,
    base_minor        BIGINT      NOT NULL,
    per_km_minor      BIGINT      NOT NULL,
    per_minute_minor  BIGINT      NOT NULL,
    -- The floor a negotiation may not go under. Without it, "make me an offer"
    -- is an invitation to offer a penny.
    minimum_minor     BIGINT      NOT NULL,
    -- Surge, later. A column rather than a future migration because multiplying
    -- by 100 today costs nothing and changes no arithmetic.
    surge_bps         INT         NOT NULL DEFAULT 10000,
    effective_from    TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pricing_positive_chk CHECK (base_minor >= 0 AND per_km_minor >= 0
        AND per_minute_minor >= 0 AND minimum_minor >= 0)
);

-- "The price list in force for this category right now" — one query, newest
-- effective row first.
CREATE INDEX pricing_config_lookup_idx
    ON travel.pricing_config (category, effective_from DESC);

-- ---------------------------------------------------------------------------
-- 2. The ride
-- ---------------------------------------------------------------------------
--
-- Three fares, and they are three different facts:
--
--   suggested_fare_minor — what the pricing engine said. Advisory, always kept,
--                          because "you paid 40 when we said 32" is a question
--                          somebody will eventually ask.
--   offered_fare_minor   — what the rider put on the table. May equal the
--                          suggestion or not; it is what drivers are answering.
--   agreed_fare_minor    — what was settled on, frozen at CONFIRMED. Null until
--                          then, and never recomputed afterwards: a fare that
--                          moves after a handshake is not a handshake.

CREATE TABLE travel.ride (
    id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_id              UUID         NOT NULL,

    category              VARCHAR(16)  NOT NULL,

    pickup_latitude       DOUBLE PRECISION NOT NULL,
    pickup_longitude      DOUBLE PRECISION NOT NULL,
    pickup_label          VARCHAR(200) NOT NULL DEFAULT '',
    dropoff_latitude      DOUBLE PRECISION NOT NULL,
    dropoff_longitude     DOUBLE PRECISION NOT NULL,
    dropoff_label         VARCHAR(200) NOT NULL DEFAULT '',
    note                  VARCHAR(280) NOT NULL DEFAULT '',

    -- What the route is, as estimated at request time. Kept on the ride because
    -- the fare was computed from these numbers and a receipt has to be able to
    -- show its own working.
    distance_metres       INT          NOT NULL DEFAULT 0,
    duration_seconds      INT          NOT NULL DEFAULT 0,

    suggested_fare_minor  BIGINT       NOT NULL DEFAULT 0,
    offered_fare_minor    BIGINT       NOT NULL DEFAULT 0,
    agreed_fare_minor     BIGINT,
    currency              VARCHAR(3)   NOT NULL DEFAULT 'USD',

    -- REQUESTED | NEGOTIATING | CONFIRMED | ARRIVING | IN_TRIP | COMPLETED
    -- | CANCELLED_RIDER | CANCELLED_DRIVER | EXPIRED.
    -- DRAFT from SPECS §2 is deliberately absent: a ride that has not been
    -- requested is a screen in the app, not a row here.
    state                 VARCHAR(24)  NOT NULL DEFAULT 'REQUESTED',

    -- The driver, once there is one. Both ids: the dispatch registration (for
    -- positions) and the profile (for a name and a face, resolved through
    -- `profile` rather than copied).
    driver_worker_id      UUID,
    driver_user_id        UUID,
    -- A snapshot of the car at confirmation. Copied, not looked up: a rider's
    -- receipt must still say which vehicle collected them after the driver sells
    -- it, and `travel` has no business reading `partner`'s tables anyway.
    vehicle_label         VARCHAR(120) NOT NULL DEFAULT '',
    vehicle_plate         VARCHAR(20)  NOT NULL DEFAULT '',

    -- The messaging thread, so the app can open it without asking twice.
    conversation_id       UUID,

    -- How long the search may run before the rider is told nobody took it.
    expires_at            TIMESTAMPTZ  NOT NULL,
    requested_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    confirmed_at          TIMESTAMPTZ,
    arrived_at            TIMESTAMPTZ,
    started_at            TIMESTAMPTZ,
    completed_at          TIMESTAMPTZ,
    cancelled_at          TIMESTAMPTZ,
    cancel_reason         VARCHAR(280),
    -- Charged when a rider cancels after the driver was already on the way.
    cancel_fee_minor      BIGINT       NOT NULL DEFAULT 0,

    -- Mutual, and separate: each side rates the other, and neither can see the
    -- other's until both are in (a rule the read enforces, not this table).
    rider_rating          INT,
    driver_rating         INT,

    state_changed_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),

    -- First acceptance wins, and the loser is told. Same reasoning as
    -- dispatch.job — two drivers each believing a trip is theirs is the failure
    -- the whole negotiation has to be safe against.
    version               INT          NOT NULL DEFAULT 0,

    CONSTRAINT ride_state_chk CHECK (state IN
        ('REQUESTED', 'NEGOTIATING', 'CONFIRMED', 'ARRIVING', 'IN_TRIP',
         'COMPLETED', 'CANCELLED_RIDER', 'CANCELLED_DRIVER', 'EXPIRED')),
    CONSTRAINT ride_rating_chk CHECK (
        (rider_rating IS NULL OR rider_rating BETWEEN 1 AND 5) AND
        (driver_rating IS NULL OR driver_rating BETWEEN 1 AND 5)),
    -- A confirmed ride has a price and a driver; nothing else may.
    CONSTRAINT ride_confirmed_chk CHECK (
        state IN ('REQUESTED', 'NEGOTIATING', 'EXPIRED', 'CANCELLED_RIDER')
        OR (agreed_fare_minor IS NOT NULL AND driver_worker_id IS NOT NULL))
);

-- "My rides", newest first — the history screen and the one-live-ride check.
CREATE INDEX ride_rider_idx ON travel.ride (rider_id, requested_at DESC);
CREATE INDEX ride_driver_idx ON travel.ride (driver_user_id, requested_at DESC);
-- The expiry sweep: searches that ran out of time.
CREATE INDEX ride_open_idx ON travel.ride (state, expires_at);

-- ---------------------------------------------------------------------------
-- 3. Offers — the negotiation itself
-- ---------------------------------------------------------------------------
--
-- **A counteroffer is a row, not a field**, because there are up to two rounds
-- and both sides make them, and a pair of columns would collapse "the driver
-- asked 45, I came back with 38, they took it" into a single number nobody can
-- audit. It is also what lets a rider hold three counters from three drivers at
-- once and pick one.
--
-- This table is `travel`'s, not `dispatch`'s, and that boundary is the milestone's
-- main decision. Dispatch's offer book asks "will you do this job"; it has no
-- opinion about money and must not grow one. So a driver who wants a different
-- price *declines* the dispatch offer and posts one of these instead.

CREATE TABLE travel.ride_offer (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id        UUID        NOT NULL REFERENCES travel.ride (id) ON DELETE CASCADE,

    -- Who is offering. The driver's dispatch registration and their profile —
    -- the first is what assignment needs, the second is what a card renders.
    driver_worker_id UUID      NOT NULL,
    driver_user_id   UUID      NOT NULL,

    -- DRIVER | RIDER. Both sides counter, and which one made an offer decides
    -- who is allowed to accept it.
    party          VARCHAR(8)  NOT NULL,
    amount_minor   BIGINT      NOT NULL,
    -- 1 for the driver's first counter, 2 for the rider's answer to it, and
    -- that is the cap (CONFIG). Haggling is a feature; an auction is not.
    round          INT         NOT NULL DEFAULT 1,

    -- PENDING | ACCEPTED | DECLINED | EXPIRED | WITHDRAWN. WITHDRAWN is what
    -- every other driver's counter becomes the moment one is accepted — the same
    -- distinction dispatch draws, and for the same reason: losing a race must
    -- not read as ignoring your phone.
    state          VARCHAR(16) NOT NULL DEFAULT 'PENDING',

    expires_at     TIMESTAMPTZ NOT NULL,
    responded_at   TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT ride_offer_party_chk CHECK (party IN ('DRIVER', 'RIDER')),
    CONSTRAINT ride_offer_state_chk CHECK (state IN
        ('PENDING', 'ACCEPTED', 'DECLINED', 'EXPIRED', 'WITHDRAWN')),
    CONSTRAINT ride_offer_amount_chk CHECK (amount_minor > 0),
    CONSTRAINT ride_offer_round_chk CHECK (round BETWEEN 1 AND 8)
);

-- What is on the rider's screen: the live counters for this ride.
CREATE INDEX ride_offer_ride_idx ON travel.ride_offer (ride_id, state);
-- One driver's own thread of the negotiation, and the "you already countered"
-- check.
CREATE INDEX ride_offer_driver_idx ON travel.ride_offer (ride_id, driver_worker_id);
-- The expiry sweep.
CREATE INDEX ride_offer_open_idx ON travel.ride_offer (state, expires_at);

-- ---------------------------------------------------------------------------
-- 4. A starting price list
-- ---------------------------------------------------------------------------
-- Seeded rather than left empty, unlike the music catalog: a quote endpoint with
-- no price list can only refuse, and there is no admin surface to fill it in
-- yet. These are round numbers meant to be replaced, not defended.

INSERT INTO travel.pricing_config
    (category, base_minor, per_km_minor, per_minute_minor, minimum_minor) VALUES
    ('BIKE',    100,  60,  8,  200),
    ('SCOOTER', 120,  75, 10,  250),
    ('CAR',     200, 120, 15,  500),
    ('COMFORT', 300, 170, 22,  800),
    ('XL',      400, 220, 28, 1100),
    ('VAN',     500, 260, 32, 1400);

-- ---------------------------------------------------------------------------
-- 5. Policy knobs (SPECS §2, §14)
-- ---------------------------------------------------------------------------

INSERT INTO platform.config (key, value, note) VALUES
    ('travel.negotiation.max.rounds', '2',
     'Counters allowed in total: the driver''s, and the rider''s answer to it. '
     'Haggling is a feature; an auction is not'),
    ('travel.offer.ttl.seconds', '45',
     'How long a counteroffer stands. Longer than a dispatch offer, because a '
     'price is a decision and being sent one is not'),
    ('travel.request.ttl.seconds', '300',
     'How long the search runs before the rider is told nobody took it'),
    ('travel.cancel.fee.minor', '200',
     'Charged when a rider cancels after the driver was already on the way. '
     'Never before that — changing your mind is free until somebody drove'),
    ('travel.rating.window.days', '7',
     'How long after a trip either side may still rate the other'),
    ('travel.route.road.factor.bps', '13000',
     'Straight-line distance × this ÷ 10000 ≈ road distance, until a routing '
     'provider is wired in. 1.3 is the usual urban figure'),
    ('travel.route.speed.kmh', '24',
     'Assumed average city speed, for the duration half of a quote');

-- ---------------------------------------------------------------------------
-- 6. A ledger kind for a fare, and the car a rider is looking for
-- ---------------------------------------------------------------------------
--
-- Two small changes in other modules' tables, both here rather than in their own
-- migration because they exist only to serve this milestone.
--
-- **RIDE_FARE.** A fare could ride on `TRANSFER` — it is one, mechanically — but
-- a year of statements is the thing this decision is really about, and "Transfer"
-- next to a trip is a line nobody can read. Rides carry no commission (SPECS §1;
-- the platform's revenue is M4's tokens), so unlike a delivery this is a single
-- movement rather than a split, and it deserves a name.

ALTER TABLE payments.ledger_entry DROP CONSTRAINT ledger_kind_chk;
ALTER TABLE payments.ledger_entry ADD CONSTRAINT ledger_kind_chk CHECK (kind IN (
    'TOPUP', 'HOLD', 'RELEASE', 'CAPTURE', 'FEE', 'COURIER_FEE', 'TIP',
    'REFUND', 'PAYOUT', 'STAKE', 'STAKE_RELEASE', 'TOKEN_PURCHASE',
    'TOKEN_SPEND', 'REWARD', 'RIDE_FARE', 'TRANSFER', 'ADJUSTMENT'));

-- **The car, on the dispatch registration.** A rider standing on a kerb needs to
-- know which vehicle is theirs, and the only thing that answers that is a make
-- and a plate — which live in `partner`, a vertical. `travel` reading them would
-- be a vertical→vertical dependency, exactly what ARCHITECTURE §2 keeps out.
--
-- So `partner` pushes them down to `dispatch` at provisioning and whenever the
-- active vehicle changes, in the same direction it already provisions. Dispatch
-- hands them back on an assignment. That also makes them a *snapshot*: a receipt
-- still names the car that collected you after the driver sells it.

ALTER TABLE dispatch.worker
    ADD COLUMN vehicle_label VARCHAR(120) NOT NULL DEFAULT '',
    ADD COLUMN vehicle_plate VARCHAR(20)  NOT NULL DEFAULT '';
