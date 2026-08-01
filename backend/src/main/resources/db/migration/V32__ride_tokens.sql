-- Phase 3 · Milestone 4: ride-hailing tokens (SPECS.md §4, §1).
--
-- This is the milestone where the platform starts earning from a ride. M3 built
-- the loop and settled the fare as a single rider→driver transfer with **no
-- commission**, because the vision's transport model is not a cut of the fare —
-- it is a token the driver spends to take the job. So the fare stays entirely
-- the driver's, and what GojoGo sells is the right to accept.
--
-- Two tables, in two schemas, and the split is this milestone's main boundary
-- call:
--
--   payments.token_pack     — how you *buy* tokens. A size and a price, in the
--                             one platform currency, and nothing else. No
--                             vertical vocabulary at all.
--   travel.ride_token_price — how many tokens a *ride* costs, by vehicle
--                             category and distance band.
--
-- SPECS §4 puts both in `payments` (`payments.token_policy`). The second one
-- moved because it is keyed on a `com.gojogo.dispatch.VehicleCategory` and a
-- distance in metres — vocabulary a platform money module has no business
-- learning, and which it could only store as opaque strings it cannot check.
-- Next to `travel.pricing_config` it is what it actually is: the other half of
-- the same price change. What the rider pays and what the driver pays move
-- together, and now they are edited together.

-- ---------------------------------------------------------------------------
-- 1. What a token is worth
-- ---------------------------------------------------------------------------
--
-- A token is a ledger credit in the TOKENS bucket, and the ledger has exactly
-- one amount per entry — so the bucket holds **minor units like every other
-- bucket**, and a "token" is a fixed number of them (`payments.token.value.minor`).
-- The ledger stays money; the product stays tokens; the conversion happens in
-- one place (`TokenApi`).
--
-- The alternative — a bucket counting tokens rather than money — would make a
-- purchase an entry whose two sides are in different units, which is not
-- double-entry bookkeeping, it is two single-sided writes with a hyphen between
-- them.

CREATE TABLE payments.token_pack (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name          VARCHAR(60)  NOT NULL,
    -- How many tokens the driver ends up with.
    tokens        INT          NOT NULL,
    -- What they pay out of AVAILABLE for them. A pack priced below face value
    -- is a bonus, and the bonus is funded by PLATFORM as its own ledger entry —
    -- the ledger cannot create money, and "the platform gave you two tokens" is
    -- the truthful way to record a discount.
    price_minor   BIGINT       NOT NULL,
    active        BOOLEAN      NOT NULL DEFAULT true,
    sort_order    INT          NOT NULL DEFAULT 0,
    note          VARCHAR(200) NOT NULL DEFAULT '',
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT token_pack_size_chk  CHECK (tokens > 0),
    CONSTRAINT token_pack_price_chk CHECK (price_minor > 0)
);

CREATE INDEX token_pack_active_idx ON payments.token_pack (active, sort_order);

-- Seeded rather than left empty, for the same reason travel's price list was: a
-- purchase endpoint with no packs can only refuse, and there is no admin surface
-- to fill it in yet. Round numbers meant to be replaced, not defended — with a
-- token at $1, the larger packs are the discount.
INSERT INTO payments.token_pack (name, tokens, price_minor, sort_order, note) VALUES
    ('Starter',  5,   500, 1, 'Five rides'' worth, at face value'),
    ('Standard', 12, 1100, 2, 'One token free'),
    ('Pro',      30, 2600, 3, 'Four tokens free'),
    ('Fleet',    75, 6000, 4, 'Fifteen tokens free');

-- ---------------------------------------------------------------------------
-- 2. What a ride costs the driver
-- ---------------------------------------------------------------------------
--
-- Bands are **upper bounds, not ranges**: the winning row is the cheapest
-- `up_to_metres` that still covers the trip, and every category ends with a
-- catch-all. A pair of (min, max) columns can be left with a gap in it, and a
-- gap here means a ride that costs nothing and nobody notices for a month.
--
-- Effective-dated like every other price in this system, and for the same
-- reason: raising the token price must not change what a ride that already
-- happened cost.

CREATE TABLE travel.ride_token_price (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- A com.gojogo.dispatch.VehicleCategory name, the same vocabulary
    -- travel.pricing_config uses.
    category       VARCHAR(16) NOT NULL,
    -- Trips up to this distance pay `tokens`. The last row per category is the
    -- catch-all.
    up_to_metres   INT         NOT NULL,
    tokens         INT         NOT NULL,
    effective_from TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Zero is allowed and is the off switch: a category priced at zero tokens
    -- charges nothing and writes no ledger entry, which is a cleaner way to turn
    -- the model off in a market than a boolean nobody remembers to check.
    CONSTRAINT ride_token_price_chk CHECK (tokens >= 0 AND up_to_metres > 0)
);

CREATE INDEX ride_token_price_lookup_idx
    ON travel.ride_token_price (category, effective_from DESC, up_to_metres);

-- Three bands per category, so the price tracks the fare rather than the trip:
-- a driver who takes a long expensive ride pays more for it than one who takes a
-- two-kilometre hop, which is what stops the short rides being the only ones
-- anybody wants.
INSERT INTO travel.ride_token_price (category, up_to_metres, tokens) VALUES
    ('BIKE',     3000, 1), ('BIKE',    10000, 2), ('BIKE',    2000000000, 3),
    ('SCOOTER',  3000, 1), ('SCOOTER', 10000, 2), ('SCOOTER', 2000000000, 3),
    ('CAR',      3000, 1), ('CAR',     10000, 2), ('CAR',     2000000000, 4),
    ('COMFORT',  3000, 2), ('COMFORT', 10000, 3), ('COMFORT', 2000000000, 5),
    ('XL',       3000, 2), ('XL',      10000, 4), ('XL',      2000000000, 6),
    ('VAN',      3000, 2), ('VAN',     10000, 4), ('VAN',     2000000000, 7);

-- ---------------------------------------------------------------------------
-- 3. What this ride actually cost its driver
-- ---------------------------------------------------------------------------
--
-- Frozen onto the ride at CONFIRMED, exactly like the fare and for the same
-- reason: it is what a refund gives back, and re-deriving it later from a price
-- list that has since changed would return the wrong number to somebody who can
-- check. Zero for every ride that already happened, which is the truth — nothing
-- charged tokens before this migration ran.

ALTER TABLE travel.ride
    ADD COLUMN token_cost INT NOT NULL DEFAULT 0;

-- ---------------------------------------------------------------------------
-- 4. Policy knobs (SPECS §4, §14)
-- ---------------------------------------------------------------------------

INSERT INTO platform.config (key, value, note) VALUES
    ('payments.token.value.minor', '100',
     'What one ride token is worth in minor units. The TOKENS bucket holds '
     'money like every other bucket; this is the only place tokens become one'),
    ('payments.tokens.low.threshold', '3',
     'Below this many tokens a driver gets a push. Low enough to be a warning '
     'rather than a nag, high enough to arrive before they stop being offered work'),
    ('payments.tokens.welcome.grant', '5',
     'Tokens credited from PLATFORM when a driver is approved. Without it the '
     'first thing a newly approved driver sees is being filtered out of every '
     'search for a reason nothing has told them about yet');

-- ---------------------------------------------------------------------------
-- 5. Nothing to alter
-- ---------------------------------------------------------------------------
--
-- TOKEN_PURCHASE and TOKEN_SPEND have been legal ledger kinds since V23, written
-- there before anything used them. A token refund rides on the existing REFUND
-- kind rather than a new one: it is a movement going back, which is what that
-- kind means, and the (RIDE, ride id) reference already pairs it with the spend
-- it reverses.
