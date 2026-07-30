-- Identity verification (SPECS.md §4 "KYC"): the vendor-backed half of what the
-- partner module has been doing by hand.
--
-- Until now, proving who you are meant uploading an ID card into a private S3
-- prefix and waiting for a human to look at it. That is impl #1 of the
-- IdentityVerificationApi SPECS §4 reserved; this is impl #2 — Sumsub — and the
-- interface is what makes the vendor a config swap rather than a rewrite.
--
-- What lives here is deliberately thin: a *verdict*, not evidence. The documents,
-- the selfie, the liveness video and the extracted personal data all stay with
-- the vendor, which is the entire point of using one — GojoGo's database should
-- not become a second copy of everyone's passport. What we keep is the answer
-- (are they verified), enough to re-ask (the applicant id), and enough to tell
-- them why not.
--
-- user_id references profile.user_profile as a plain UUID — no foreign keys
-- across schemas, ever (ARCHITECTURE.md §4).

CREATE SCHEMA IF NOT EXISTS kyc;

CREATE TABLE kyc.identity_verification (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    -- One verification per person, not per application: a courier who later
    -- opens a restaurant is the same human and does not verify twice.
    user_id         UUID         NOT NULL,

    provider        VARCHAR(24)  NOT NULL DEFAULT 'SUMSUB',
    -- The vendor's handle for this person. Null until they actually start —
    -- an access token is minted before any applicant exists on their side.
    applicant_id    VARCHAR(64),
    -- Which check they were put through, recorded because a level's rules
    -- change over time and "verified" without it is not a claim you can audit.
    level_name      VARCHAR(80)  NOT NULL DEFAULT '',

    status          VARCHAR(32)  NOT NULL DEFAULT 'NOT_STARTED',
    -- The vendor's own words, in two registers: `reason` is written for the
    -- applicant to read (Sumsub's clientComment), `moderation_note` is the
    -- reviewer's internal one. Both nullable; a GREEN answer has neither.
    reason           VARCHAR(600),
    moderation_note  VARCHAR(600),
    -- Machine-readable rejection causes (Sumsub reject labels), comma-separated.
    -- Stored flat: nothing joins on them, they are for display and support.
    reject_labels    VARCHAR(400) NOT NULL DEFAULT '',

    -- When the vendor last said something, by their clock — so an out-of-order
    -- webhook can be recognised as stale rather than overwriting a newer answer.
    provider_event_at TIMESTAMPTZ,
    verified_at       TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT identity_verification_status_chk
        CHECK (status IN ('NOT_STARTED', 'PENDING', 'IN_REVIEW', 'VERIFIED',
                          'RESUBMISSION_REQUESTED', 'REJECTED')),
    -- VERIFIED is the only state that may carry a verification time, and it
    -- must carry one: "verified since when" is the question an auditor asks.
    CONSTRAINT identity_verification_verified_chk
        CHECK ((status = 'VERIFIED') = (verified_at IS NOT NULL))
);

CREATE UNIQUE INDEX identity_verification_user_idx
    ON kyc.identity_verification (user_id);
-- The webhook arrives knowing the vendor's id and nothing else.
CREATE UNIQUE INDEX identity_verification_applicant_idx
    ON kyc.identity_verification (applicant_id)
    WHERE applicant_id IS NOT NULL;

-- Webhook idempotency. Sumsub retries on any non-2xx, and a retried
-- applicantReviewed must not re-fire the domain event that flips a partner's
-- verified badge. The row *is* the lock: the insert is what claims the delivery.
CREATE TABLE kyc.provider_event (
    id           VARCHAR(80)  PRIMARY KEY,
    type         VARCHAR(48)  NOT NULL DEFAULT '',
    applicant_id VARCHAR(64),
    received_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Deliveries are only interesting while they are recent enough to be retried;
-- this index is what a later prune reads.
CREATE INDEX provider_event_received_idx ON kyc.provider_event (received_at);
