-- Phase 3 · Milestone 2: driver onboarding completes (SPECS.md §4).
--
-- M1 gave an approved driver somewhere to land. What is still missing is
-- everything between "I would like to drive" and an approval worth granting: the
-- car, its papers, and the $30 the vision stakes on somebody's good conduct.
--
-- The application object itself is unchanged — that was the point of making
-- `partner` generic in 2b M6. What arrives here is a vehicle table hanging off
-- it, and five columns of money on the account.

-- ---------------------------------------------------------------------------
-- 1. The stake, and the fee it pays for
-- ---------------------------------------------------------------------------
--
-- **The stake is a ledger movement, not a column.** These columns are a
-- *record* of one — the money itself lives in `payments` as a transfer from the
-- applicant's AVAILABLE into their own STAKING bucket, which is why there is no
-- balance here to drift out of step with the ledger. What is stored is what the
-- application needs to answer on its own: has it been paid, how much, and has
-- the KYC fee come out of it yet.
--
-- It is a **precondition for submission, not for approval** (SPECS §4): staking
-- is what funds verification, so it happens before a human spends time on the
-- application rather than after they have.

ALTER TABLE partner.partner_account
    ADD COLUMN stake_amount_minor BIGINT      NOT NULL DEFAULT 0,
    ADD COLUMN stake_paid_at      TIMESTAMPTZ,
    -- Set when the stake goes back (rejection, or a withdrawn application).
    -- A suspension does *not* release it: the stake is what a penalty and a
    -- verification reward are paid from, and handing it back at the moment
    -- somebody is in trouble defeats the mechanism.
    ADD COLUMN stake_released_at  TIMESTAMPTZ,
    ADD COLUMN kyc_fee_minor      BIGINT      NOT NULL DEFAULT 0,
    ADD COLUMN kyc_fee_paid_at    TIMESTAMPTZ;

-- ---------------------------------------------------------------------------
-- 2. Vehicles
-- ---------------------------------------------------------------------------
--
-- In `partner` rather than in `dispatch`, and that is the boundary call worth
-- writing down. A vehicle is a *claim a human reviews* — papers, expiry dates, a
-- plate somebody has to match against a photo — which is precisely what the
-- partner module is for. Dispatch needs one fact out of all of it: which
-- category this worker can be sent, which arrives through the provisioning API
-- at approval. Putting the table in dispatch would have made the matching module
-- responsible for insurance documents.
--
-- **Multiple vehicles, exactly one active.** A driver with a car and a van
-- verifies each separately (SPECS §4), and the active one is what dispatch
-- matches on.

CREATE TABLE partner.vehicle (
    id                      UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id              UUID         NOT NULL
        REFERENCES partner.partner_account (id) ON DELETE CASCADE,
    -- Denormalised from the account so the private-upload prefix check and the
    -- owner check never need a join. The application cannot change hands.
    user_id                 UUID         NOT NULL,

    -- A com.gojogo.dispatch.VehicleCategory name. Stored as text rather than
    -- shared as an enum type: this column is read by a human reviewer as often
    -- as by code, and a rollback must not make an old row unreadable.
    category                VARCHAR(16)  NOT NULL,
    make                    VARCHAR(60)  NOT NULL DEFAULT '',
    model                   VARCHAR(60)  NOT NULL DEFAULT '',
    year                    INT,
    color                   VARCHAR(30)  NOT NULL DEFAULT '',
    plate                   VARCHAR(20)  NOT NULL DEFAULT '',
    -- Plates are unique per *region*, never globally: the same string is a
    -- different car in another country, and a global unique index would refuse
    -- the second market this platform opens in.
    region                  VARCHAR(60)  NOT NULL DEFAULT '',

    -- SUBMITTED | APPROVED | COMMUNITY_VERIFIED | FLAGGED | RETIRED.
    -- COMMUNITY_VERIFIED is Phase 3 M5's passenger confirmation; the state
    -- exists now so the badge has somewhere to come from and the reviewer's
    -- vocabulary doesn't change under them later.
    state                   VARCHAR(24)  NOT NULL DEFAULT 'SUBMITTED',
    active                  BOOLEAN      NOT NULL DEFAULT false,

    -- Dates, not timestamps: a policy expires on a day, in a timezone nobody
    -- recorded, and pretending to a second's precision would be a lie the
    -- auto-suspend sweep then acts on.
    registration_expires_on DATE,
    insurance_expires_on    DATE,

    review_note             VARCHAR(400),
    -- Set by the expiry sweep so a driver can be told *which* paper lapsed, and
    -- so a re-upload can clear it without a reviewer.
    flagged_at              TIMESTAMPTZ,

    created_at              TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT vehicle_state_chk CHECK (state IN
        ('SUBMITTED', 'APPROVED', 'COMMUNITY_VERIFIED', 'FLAGGED', 'RETIRED')),
    CONSTRAINT vehicle_year_chk CHECK (year IS NULL OR (year >= 1950 AND year <= 2100))
);

CREATE INDEX vehicle_account_idx ON partner.vehicle (account_id, created_at);

-- One active vehicle per application. A partial unique index rather than a
-- flag the service is trusted to maintain: "activate this one" is two writes,
-- and the database is the only thing that can hold the invariant between them.
CREATE UNIQUE INDEX vehicle_one_active_idx
    ON partner.vehicle (account_id) WHERE active;

-- The same plate cannot be registered twice in one region while it is live. A
-- retired vehicle is excluded, because selling a car and somebody else
-- registering it is the normal case, not fraud.
CREATE UNIQUE INDEX vehicle_plate_region_idx
    ON partner.vehicle (lower(region), lower(plate))
    WHERE state <> 'RETIRED' AND plate <> '';

-- The expiry sweep's query: what lapses soonest. Partial, because a vehicle
-- with no dates on file is not something a sweep can act on.
CREATE INDEX vehicle_expiry_idx
    ON partner.vehicle (registration_expires_on, insurance_expires_on)
    WHERE state IN ('APPROVED', 'COMMUNITY_VERIFIED');

-- Registration + insurance. Private objects under the applicant's own prefix,
-- exactly like the identity papers in V19 — the reviewer reads one through a
-- short-lived signed GET and this table stores keys, never URLs.
CREATE TABLE partner.vehicle_document (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id   UUID         NOT NULL
        REFERENCES partner.vehicle (id) ON DELETE CASCADE,
    -- REGISTRATION | INSURANCE.
    kind         VARCHAR(24)  NOT NULL,
    object_key   VARCHAR(400) NOT NULL,
    content_type VARCHAR(80)  NOT NULL DEFAULT '',
    uploaded_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT vehicle_document_kind_chk CHECK (kind IN ('REGISTRATION', 'INSURANCE'))
);

-- Re-uploading a kind replaces it, so one row per kind per vehicle.
CREATE UNIQUE INDEX vehicle_document_kind_idx
    ON partner.vehicle_document (vehicle_id, kind);

-- Photos of the car, and these are ordinary public media — they end up on a
-- rider's screen next to a plate number, which is the whole point of them. The
-- papers are private and the photos are not, and keeping the two in separate
-- tables is what stops that distinction being a boolean somebody gets wrong.
CREATE TABLE partner.vehicle_photo (
    vehicle_id UUID         NOT NULL
        REFERENCES partner.vehicle (id) ON DELETE CASCADE,
    url        VARCHAR(600) NOT NULL,
    sort_order INT          NOT NULL DEFAULT 0,

    PRIMARY KEY (vehicle_id, url)
);
CREATE INDEX vehicle_photo_order_idx ON partner.vehicle_photo (vehicle_id, sort_order);

-- ---------------------------------------------------------------------------
-- 3. Policy knobs (SPECS §4, §14)
-- ---------------------------------------------------------------------------
-- Compiled-in defaults match these exactly. Amounts are minor units of the
-- platform currency, as everywhere else money appears.

INSERT INTO platform.config (key, value, note) VALUES
    ('partner.stake.driver.minor', '3000',
     'The vision''s $30 good-conduct stake, held in the driver''s own STAKING bucket'),
    ('partner.stake.courier.minor', '3000',
     'The same for couriers. Separate key so the two can diverge without a deploy'),
    ('partner.kyc.fee.minor', '500',
     'Charged out of the stake at submission — an ID check costs real money. '
     'A starting point, not a commitment'),
    ('partner.kyc.retry.fee.minor', '0',
     'Charged again on resubmission after a failed check. Zero by default: '
     'a blurry photo is not something to fine somebody for'),
    ('partner.vehicle.expiry.grace.days', '7',
     'How long after a registration or insurance lapses before the vehicle is '
     'flagged and its driver stops receiving work'),
    ('partner.vehicle.photos.max', '5',
     'Photos per vehicle'),
    ('partner.vehicle.required.driver', 'true',
     'A driver must have an active, papered vehicle to submit. Couriers must '
     'not — a bicycle has no registration to show');
