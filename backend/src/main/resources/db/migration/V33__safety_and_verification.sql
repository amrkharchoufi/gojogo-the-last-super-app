-- Phase 3 · Milestone 5: community vehicle verification + the safety pack
-- (SPECS.md §4 "Community vehicle verification", §10 "SOS" + "Live share links").
--
-- Two halves that look unrelated and are not. Both answer the same question a
-- rider asks on a kerb at night: *is this the car, and does anyone know I'm in
-- it.* The first half makes the answer to "is this the car" something other
-- passengers have checked; the second makes the answer to "does anyone know"
-- a link somebody outside this app can open.
--
-- Four tables in four schemas, plus columns on two existing ones:
--
--   partner.vehicle_verification — an invitation to a passenger, and their answer
--   profile.emergency_contact    — who to tell
--   share.share_token            — a public, expiring pointer at one thing
--   travel.ride  (+ columns)     — which car actually did the trip, and the SOS flag
--   dispatch.worker (+ columns)  — the vehicle id and badge, pushed down as usual

-- ---------------------------------------------------------------------------
-- 1. Which vehicle did the trip
-- ---------------------------------------------------------------------------
--
-- A vehicle lives in `partner` and dispatch has been carrying a *description*
-- of it since V31 ("White Dacia Logan" + a plate) precisely so no vertical has
-- to read across at partner's tables. Community verification needs one thing
-- more: which row that description came from, so a passenger's answer lands on
-- the vehicle they actually rode in rather than on whatever is active by the
-- time they open the app.
--
-- So the id travels the same way the label did — pushed down at provisioning
-- and whenever the driver switches cars — and `travel` snapshots it onto the
-- ride at CONFIRMED, next to the plate it already snapshots and for the same
-- reason: a receipt should still name the car that collected you after the
-- driver sells it.
--
-- `vehicle_verified` rides along because it is a *badge*, and a badge is only
-- worth having where it is seen. Nullable/false everywhere for rows written
-- before this migration, which is the truth: nothing was verified yet.

ALTER TABLE dispatch.worker
    ADD COLUMN vehicle_id       UUID,
    ADD COLUMN vehicle_verified BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE travel.ride
    ADD COLUMN vehicle_id       UUID,
    ADD COLUMN vehicle_verified BOOLEAN NOT NULL DEFAULT false;

-- ---------------------------------------------------------------------------
-- 2. The passenger's verification
-- ---------------------------------------------------------------------------
--
-- One row is one *invitation*, and its answer if it ever gets one. The two are
-- the same row rather than an invitation table and a response table because an
-- unanswered invitation is the interesting state — it is what the expiry sweep
-- looks for, and what "we already asked somebody" means when the next trip
-- finishes.
--
-- **Unique on the ride**, not on (vehicle, passenger): a trip produces at most
-- one invitation, which is what makes the listener safe to run twice. The
-- vehicle's own limit — at most `partner.verification.max.invites` attempts
-- before it gives up — is a count over these rows, not a constraint, because
-- the cap is policy and lives in the config registry.
--
-- The five answers are five columns rather than a JSON blob or a score. They
-- are the questions SPECS §4 names, a moderator reads them individually when a
-- vehicle is flagged, and "the driver was not the person in the app" is a
-- different problem from "the car was filthy".

CREATE TABLE partner.vehicle_verification (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id     UUID        NOT NULL REFERENCES partner.vehicle(id) ON DELETE CASCADE,
    account_id     UUID        NOT NULL REFERENCES partner.partner_account(id) ON DELETE CASCADE,
    -- The profile being asked. Not a foreign key for the same reason nothing
    -- else in this schema points at profile: modules own their own tables.
    passenger_id   UUID        NOT NULL,
    driver_user_id UUID        NOT NULL,
    -- The trip that earned the invitation. One invitation per trip, and the
    -- uniqueness below is what makes a redelivered TripCompleted harmless.
    ride_id        UUID        NOT NULL,
    -- PENDING → CONFIRMED | REJECTED | EXPIRED. A varchar rather than an enum
    -- type for the same reason as everywhere else here: adding a state should
    -- not need a migration and a deploy in lockstep.
    status         VARCHAR(16) NOT NULL DEFAULT 'PENDING',

    -- The five questions, null until answered.
    driver_matched  BOOLEAN,
    photos_matched  BOOLEAN,
    plate_matched   BOOLEAN,
    roadworthy      BOOLEAN,
    no_fraud        BOOLEAN,
    comment         VARCHAR(500) NOT NULL DEFAULT '',

    -- What the passenger was paid, if anything. Recorded here rather than
    -- inferred from the ledger so the row can say "we already paid this" —
    -- the ledger is the money, this is the decision.
    reward_minor   BIGINT      NOT NULL DEFAULT 0,

    expires_at     TIMESTAMPTZ NOT NULL,
    answered_at    TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT vehicle_verification_ride_uk UNIQUE (ride_id),
    CONSTRAINT vehicle_verification_status_chk
        CHECK (status IN ('PENDING', 'CONFIRMED', 'REJECTED', 'EXPIRED'))
);

-- "Has this vehicle got an invitation out, and how many has it had?"
CREATE INDEX vehicle_verification_vehicle_idx
    ON partner.vehicle_verification (vehicle_id, created_at DESC);

-- "What am I being asked to confirm?" — the passenger's own list.
CREATE INDEX vehicle_verification_passenger_idx
    ON partner.vehicle_verification (passenger_id, status, expires_at DESC);

-- The sweep.
CREATE INDEX vehicle_verification_expiry_idx
    ON partner.vehicle_verification (status, expires_at);

-- The reward comes out of the driver's stake, so the application row has to
-- know what has been taken out of it — the same accounting `kyc_fee_minor`
-- does. Without this a driver whose stake has paid three rewards still looks
-- fully staked, and a release would hand back money that is already gone.
ALTER TABLE partner.partner_account
    ADD COLUMN reward_paid_minor BIGINT NOT NULL DEFAULT 0;

-- ---------------------------------------------------------------------------
-- 3. Who to tell
-- ---------------------------------------------------------------------------
--
-- In `profile` rather than in `travel`, because an emergency contact is a fact
-- about a person and not about a trip — a delivery, a story-share and anything
-- else that ever needs one should read the same list rather than growing a
-- second.
--
-- **A phone number, and optionally a profile.** Most people's emergency
-- contact is not on GojoGo, so the number is the required half and the link is
-- the bonus: a linked contact gets a push the instant SOS is pressed, and an
-- unlinked one gets the message the phone's own SMS composer sends, which is
-- the only channel that actually works while SNS SMS is still sandboxed
-- (PROGRESS "Needs YOU" #3). Storing the number does not make us able to text
-- it — it makes the app able to.

CREATE TABLE profile.emergency_contact (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id   UUID         NOT NULL REFERENCES profile.user_profile(id) ON DELETE CASCADE,
    name         VARCHAR(80)  NOT NULL,
    phone        VARCHAR(32)  NOT NULL,
    relationship VARCHAR(40)  NOT NULL DEFAULT '',
    -- Set when this contact is also on GojoGo, which is what turns an SOS into
    -- a push rather than a message somebody has to send by hand.
    linked_profile_id UUID,
    sort_order   INT          NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT emergency_contact_name_chk  CHECK (length(btrim(name)) > 0),
    CONSTRAINT emergency_contact_phone_chk CHECK (length(btrim(phone)) > 2)
);

CREATE INDEX emergency_contact_owner_idx
    ON profile.emergency_contact (profile_id, sort_order);

-- The same person twice is a mistake, not a preference.
CREATE UNIQUE INDEX emergency_contact_phone_uk
    ON profile.emergency_contact (profile_id, phone);

-- ---------------------------------------------------------------------------
-- 4. A public link to one thing
-- ---------------------------------------------------------------------------
--
-- Its own schema and its own module, because a share token is not a travel
-- concept: the same mechanism backs a shared delivery, and later
-- `https://gojogo.app/s/{token}` for content. What it stores is a *pointer* —
-- a kind and an id — and never a payload. The payload is rendered on read by
-- the module that owns the kind, through a `ShareableResource` implementation,
-- which is the fourth instance of the plugin shape `ConversationGuard`,
-- `ModeratableContent` and `WorkerEligibility` already use, and for the same
-- reason: a platform module must not depend on a vertical.
--
-- Storing a payload instead would mean a tracking link that shows where the car
-- was when the link was made. That is not a tracking link.

CREATE SCHEMA IF NOT EXISTS share;

CREATE TABLE share.share_token (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- The URL-safe secret. Long enough that guessing one is not a way to watch
    -- a stranger's trip: this is the only thing between the public internet and
    -- somebody's live position.
    token       VARCHAR(64) NOT NULL,
    -- What it points at, in the owning module's vocabulary ("ride").
    kind        VARCHAR(24) NOT NULL,
    ref_id      UUID        NOT NULL,
    -- Who minted it, so a person can see and revoke their own links.
    owner_id    UUID        NOT NULL,
    -- Why it exists. SOS links are marked because they are not the same act as
    -- sharing a trip with a friend and should not be revocable by a tap.
    reason      VARCHAR(16) NOT NULL DEFAULT 'SHARE',
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked_at  TIMESTAMPTZ,
    -- Cheap evidence that a link was actually used, which is the only thing
    -- that distinguishes "I shared my trip" from "I meant to".
    view_count  INT         NOT NULL DEFAULT 0,
    last_seen_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT share_token_uk UNIQUE (token),
    CONSTRAINT share_token_reason_chk CHECK (reason IN ('SHARE', 'SOS'))
);

-- "Is there already a live link for this trip?" — minting is idempotent per
-- (kind, ref, owner, reason) so tapping Share twice does not scatter secrets.
CREATE INDEX share_token_ref_idx ON share.share_token (kind, ref_id, owner_id);

-- The purge.
CREATE INDEX share_token_expiry_idx ON share.share_token (expires_at);

-- ---------------------------------------------------------------------------
-- 5. SOS
-- ---------------------------------------------------------------------------
--
-- Two columns on the ride and no table. An SOS is a *flag on a trip* — the trip
-- is the record, and a separate incident table would immediately need every
-- field the ride already has. `sos_by` is kept because a driver can press it
-- too, and "who raised it" is the first question an operator asks.

ALTER TABLE travel.ride
    ADD COLUMN sos_at TIMESTAMPTZ,
    ADD COLUMN sos_by UUID;

-- The operator's list: flagged trips, newest first. Partial, because the
-- overwhelming majority of rides will never have one.
CREATE INDEX ride_sos_idx ON travel.ride (sos_at DESC) WHERE sos_at IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 6. Policy knobs (SPECS §4, §10, §14)
-- ---------------------------------------------------------------------------

INSERT INTO platform.config (key, value, note) VALUES
    ('partner.verification.reward.minor', '300',
     'Paid to a passenger who verifies a vehicle, out of that driver''s STAKING '
     'bucket. It is the driver''s own money: verification is what the stake funds'),
    ('partner.verification.invite.ttl.hours', '48',
     'How long a passenger has to answer before the invitation lapses and the '
     'next completed trip asks somebody else'),
    ('partner.verification.max.invites', '3',
     'Attempts before a vehicle stops being offered for community verification. '
     'Without a cap an unverifiable car asks every passenger it ever carries'),
    ('profile.emergency.contacts.max', '5',
     'How many emergency contacts one person may keep (SPECS §10)'),
    ('safety.emergency.number', '112',
     'Dialled by the SOS screen when no region-specific number is configured. '
     '112 works across the EU and on most GSM networks worldwide. Override per '
     'region with safety.emergency.number.<REGION>, e.g. safety.emergency.number.MA'),
    ('safety.share.base.url', 'https://gojogo.app/s/',
     'Prefix for a public tracking link. The path it points at is served by '
     'GET /v1/share/{token}; this is what the universal-link route will map to'),
    ('safety.share.ttl.minutes', '180',
     'How long a trip share link lives from the moment it is minted. Long enough '
     'to outlast the trip, short enough that a stale link stops working'),
    ('safety.share.grace.minutes', '60',
     'How long a link keeps resolving after the trip ends, so the person watching '
     'sees the arrival rather than a dead page (SPECS §10)');
