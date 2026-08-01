-- Phase 3 · Milestone 1: the platform `dispatch` module (SPECS.md §3).
--
-- Two things have been waiting on this table set since 2b M6. A DRIVER or
-- COURIER application could be filed, KYC'd and reviewed, and then an approval
-- refused with a 409 because there was nowhere for an approved driver to *land*.
-- And GojoDelivery's courier is a name and a rating invented by a scheduled job
-- walking a timeline, because no real person could be offered the work.
--
-- This migration is the landing place and the offer book: who is out there, where
-- they are right now, and which job has been offered to whom.
--
-- Deliberately Postgres and not Redis. SPECS §3 specifies Redis GEO for
-- positions, and at a scale where thousands of workers are moving that is the
-- right store. There are zero today, an ElastiCache cluster is billed by the
-- hour whether or not anybody is driving, and the read this module actually
-- performs — "available workers of kind K within N km of a point" — is a
-- bounding-box scan over a small, heavily-filtered table. The presence columns
-- live on the worker row for that reason; moving them to Redis later changes one
-- repository method and no caller.

CREATE SCHEMA IF NOT EXISTS dispatch;

-- ---------------------------------------------------------------------------
-- 1. The registry: who may be offered work
-- ---------------------------------------------------------------------------
--
-- **One table with a kind, not `driver` and `courier` side by side.** They differ
-- in which requests reach them and in nothing else — same presence, same offer
-- book, same counters — and two tables would mean two of every query above them.
-- A dual-mode person (the vision's "switch between roles") is one human with two
-- rows, which is also what makes "an accepted job in either mode makes you busy
-- in both" a one-line rule instead of a cross-table invariant.
--
-- A row is created by `DriverProvisioningApi`/`CourierProvisioningApi` at partner
-- approval and never by a person: you cannot make yourself a driver by calling an
-- endpoint, exactly as you cannot make yourself a restaurant.

CREATE TABLE dispatch.worker (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),

    -- profile.user_profile as a plain UUID — no foreign key crosses a schema
    -- boundary (ARCHITECTURE §4), because that is the line a module is
    -- extracted along.
    user_id            UUID         NOT NULL,
    -- DRIVER | COURIER.
    kind               VARCHAR(16)  NOT NULL,
    -- The application that earned it, kept for the audit trail only: dispatch
    -- never reads back into `partner`.
    partner_account_id UUID,

    -- What they can currently be sent. Until Phase 3 M2 registers vehicles this
    -- is the default for their kind; after it, the active vehicle sets it.
    category           VARCHAR(16)  NOT NULL,

    -- OFFLINE | AVAILABLE | BUSY. Availability is a person's choice, BUSY is
    -- the system's — which is why one column and not two flags: a worker cannot
    -- be simultaneously free and mid-job, and a boolean pair can express that.
    status             VARCHAR(16)  NOT NULL DEFAULT 'OFFLINE',
    -- The platform's switch, held apart from the worker's own, for the same
    -- reason delivery.merchant holds `suspended` apart from `active`: lifting a
    -- suspension must not put somebody on the road who had signed off.
    suspended          BOOLEAN      NOT NULL DEFAULT false,
    home_region        VARCHAR(60)  NOT NULL DEFAULT '',

    -- Presence. Nullable together: a worker who has never sent a position is
    -- not a candidate, however available they say they are.
    latitude           DOUBLE PRECISION,
    longitude          DOUBLE PRECISION,
    position_at        TIMESTAMPTZ,

    -- Ranking inputs. `idle_since` is what stops the nearest driver taking every
    -- job on a quiet afternoon while the next one starves.
    rating             NUMERIC(3,2) NOT NULL DEFAULT 5.00,
    rating_count       INT          NOT NULL DEFAULT 0,
    idle_since         TIMESTAMPTZ  NOT NULL DEFAULT now(),

    -- Lifetime counters (SPECS §3's "performance counters"). Rolling windows are
    -- computed from dispatch.offer, which keeps its rows; these are the cheap
    -- always-there numbers matching itself reads.
    offered_count      INT          NOT NULL DEFAULT 0,
    accepted_count     INT          NOT NULL DEFAULT 0,
    declined_count     INT          NOT NULL DEFAULT 0,
    expired_count      INT          NOT NULL DEFAULT 0,
    completed_count    INT          NOT NULL DEFAULT 0,
    cancelled_count    INT          NOT NULL DEFAULT 0,

    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT worker_kind_chk   CHECK (kind IN ('DRIVER', 'COURIER')),
    CONSTRAINT worker_status_chk CHECK (status IN ('OFFLINE', 'AVAILABLE', 'BUSY')),
    CONSTRAINT worker_rating_chk CHECK (rating >= 0 AND rating <= 5)
);

-- One registration per person per kind. This is also what makes provisioning
-- idempotent: a retried approval finds the row it already made.
CREATE UNIQUE INDEX worker_user_kind_idx ON dispatch.worker (user_id, kind);

-- The candidate scan, and the only index it needs: the status/kind pair is
-- selective enough that the latitude window is a filter rather than a seek.
CREATE INDEX worker_available_idx ON dispatch.worker (kind, status, suspended, latitude);

-- ---------------------------------------------------------------------------
-- 2. The job: one vertical asking for one worker
-- ---------------------------------------------------------------------------
--
-- Dispatch owns *finding somebody*, and stops there. The ride, the fare, the
-- basket, the money and every state after "who is doing this" belong to the
-- vertical that asked — which is why there is no fare column here and no order
-- status. What dispatch knows is a kind, an opaque id, and a place to be.

CREATE TABLE dispatch.job (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),

    -- RIDE | DELIVERY. A varchar and not an enum type: a new vertical asking for
    -- a worker should be a constant and a caller, not a migration.
    job_kind           VARCHAR(16)  NOT NULL,
    -- The vertical's own id for the thing. Opaque here on purpose.
    job_ref_id         UUID         NOT NULL,
    -- Who the work is for, carried so a worker's offer card can be decorated
    -- without dispatch reading into another module.
    requested_by       UUID,

    worker_kind        VARCHAR(16)  NOT NULL,
    -- Comma-separated acceptable categories, e.g. 'CAR,COMFORT,XL'. A list
    -- rather than one value because "an XL rider will take an XL" and "a small
    -- basket will go by bike or by car" are the same question asked twice.
    categories         VARCHAR(120) NOT NULL,

    pickup_latitude    DOUBLE PRECISION NOT NULL,
    pickup_longitude   DOUBLE PRECISION NOT NULL,
    pickup_label       VARCHAR(160) NOT NULL DEFAULT '',
    dropoff_latitude   DOUBLE PRECISION,
    dropoff_longitude  DOUBLE PRECISION,
    dropoff_label      VARCHAR(160) NOT NULL DEFAULT '',
    note               VARCHAR(200) NOT NULL DEFAULT '',

    -- SEARCHING | ASSIGNED | EXHAUSTED | CANCELLED.
    state              VARCHAR(16)  NOT NULL DEFAULT 'SEARCHING',

    -- The wave machinery (SPECS §3: rings 1 → 3 → 7 km, 15s apart). `wave` is
    -- how many have gone out; `next_wave_at` is when the poller may open
    -- another, and it is what a *scheduled* request rides on too — a courier
    -- search that must not start until the kitchen is nearly done is simply a
    -- job whose first wave is in the future.
    wave               INT          NOT NULL DEFAULT 0,
    next_wave_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    expires_at         TIMESTAMPTZ  NOT NULL,

    assigned_worker_id UUID,
    assigned_at        TIMESTAMPTZ,
    closed_at          TIMESTAMPTZ,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),

    -- Optimistic locking. First acceptance wins and every other accept must be
    -- told so rather than quietly overwrite: two couriers each believing the
    -- order is theirs is the one outcome this table exists to prevent.
    version            INT          NOT NULL DEFAULT 0,

    CONSTRAINT job_state_chk CHECK (state IN ('SEARCHING', 'ASSIGNED', 'EXHAUSTED', 'CANCELLED'))
);

-- One live dispatch per thing. A vertical retrying `requestDispatch` — or a
-- customer double-tapping — finds the search already running instead of opening
-- a second one that would offer the same trip twice.
CREATE UNIQUE INDEX job_ref_idx ON dispatch.job (job_kind, job_ref_id);
-- The poller's only query: what needs a wave, oldest first.
CREATE INDEX job_searching_idx ON dispatch.job (state, next_wave_at);

-- ---------------------------------------------------------------------------
-- 3. The offer: what was put in front of whom, and what they did about it
-- ---------------------------------------------------------------------------
--
-- Kept after it closes. A declined offer is how "acceptance rate" is computed,
-- an expired one is how a driver who leaves their phone face-down stops being
-- sent work, and both are the audit trail behind a matching complaint.

CREATE TABLE dispatch.offer (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id       UUID        NOT NULL REFERENCES dispatch.job (id) ON DELETE CASCADE,
    worker_id    UUID        NOT NULL,
    wave         INT         NOT NULL DEFAULT 0,

    -- OFFERED | ACCEPTED | DECLINED | EXPIRED | WITHDRAWN. WITHDRAWN is what
    -- happens to everybody else the moment one person accepts — distinct from
    -- EXPIRED, because it says nothing about the worker who didn't answer yet
    -- and must not count against them.
    state        VARCHAR(16) NOT NULL DEFAULT 'OFFERED',

    offered_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at   TIMESTAMPTZ NOT NULL,
    responded_at TIMESTAMPTZ,

    CONSTRAINT offer_state_chk CHECK (state IN
        ('OFFERED', 'ACCEPTED', 'DECLINED', 'EXPIRED', 'WITHDRAWN'))
);

-- The same job is never offered to the same worker twice, however many waves
-- run: a second ring that re-includes the driver who just declined is the
-- fastest way to teach them to turn the app off.
CREATE UNIQUE INDEX offer_job_worker_idx ON dispatch.offer (job_id, worker_id);
-- "What is on my screen right now", and the expiry sweep.
CREATE INDEX offer_worker_state_idx ON dispatch.offer (worker_id, state);
CREATE INDEX offer_open_idx ON dispatch.offer (state, expires_at);
-- Rolling-window performance counters read this.
CREATE INDEX offer_worker_time_idx ON dispatch.offer (worker_id, offered_at);

-- ---------------------------------------------------------------------------
-- 4. Policy knobs (SPECS §3, §14)
-- ---------------------------------------------------------------------------
-- Compiled-in defaults match these exactly, so an empty config table behaves
-- identically and a typo falls back rather than becoming a zero-radius search.

INSERT INTO platform.config (key, value, note) VALUES
    ('dispatch.wave.radii.km', '1,3,7',
     'Search rings, in order. A wave is opened per ring until somebody accepts'),
    ('dispatch.wave.interval.seconds', '15',
     'How long a ring is given before the next one widens the search'),
    ('dispatch.wave.size', '5',
     'Workers offered per ring. Larger fills faster and annoys more people'),
    ('dispatch.offer.ttl.seconds', '30',
     'How long one offer stays on a worker''s screen before it lapses'),
    ('dispatch.request.ttl.seconds', '300',
     'Total time a search runs before the vertical is told nobody took it'),
    ('dispatch.presence.stale.seconds', '60',
     'A position older than this is not a location; the worker is skipped'),
    ('dispatch.position.interval.seconds', '5',
     'How often an available worker''s app should report its position'),
    ('dispatch.rating.floor.hundredths', '0',
     'Minimum rating to be offered work, x100. 0 = no floor, which is correct '
     'until enough ratings exist for one to mean anything'),
    ('dispatch.score.weight.proximity', '60',
     'Ranking weight: how much being close matters (weights are relative)'),
    ('dispatch.score.weight.rating', '25',
     'Ranking weight: how much being well rated matters'),
    ('dispatch.score.weight.idle', '15',
     'Ranking weight: how much having waited longest matters (anti-starvation)'),
    ('dispatch.score.idle.full.seconds', '900',
     'Waiting this long counts as a full idle score; longer adds nothing'),
    ('dispatch.pickup.lead.seconds', '420',
     'How early a courier search starts before the kitchen is due to be done');
