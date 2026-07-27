-- Phase 2b · Milestone 6: partner onboarding + KYC (ARCHITECTURE.md §10 Phase 2c).
--
-- `partner` owns the *business relationship* — who applied, what they proved
-- about themselves, and whether a human said yes. It is deliberately generic:
-- a restaurant is the only kind that can be provisioned today (into
-- delivery.merchant), but a driver or a courier is the same application with a
-- different `kind`, waiting on the Phase 3 dispatch module to have something to
-- be provisioned into.
--
-- user_id references profile.user_profile as a plain UUID — no foreign keys
-- across schemas, ever (ARCHITECTURE.md §4). provisioned_ref_id points at the
-- object the approval created (a delivery.merchant id) for the same reason.

CREATE SCHEMA IF NOT EXISTS partner;

CREATE TABLE partner.partner_account (
    id                  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID         NOT NULL,
    kind                VARCHAR(16)  NOT NULL,
    status              VARCHAR(16)  NOT NULL DEFAULT 'DRAFT',

    -- Business identity. Generic on purpose: `category` is the primary trade
    -- ("Moroccan", "Burgers" for a restaurant), not a restaurant-only column.
    business_name       VARCHAR(120) NOT NULL,
    category            VARCHAR(60)  NOT NULL DEFAULT '',
    description         VARCHAR(600) NOT NULL DEFAULT '',
    logo_url            TEXT,

    contact_name        VARCHAR(120) NOT NULL DEFAULT '',
    contact_phone       VARCHAR(32)  NOT NULL DEFAULT '',
    contact_email       VARCHAR(160) NOT NULL DEFAULT '',

    country             VARCHAR(60)  NOT NULL DEFAULT '',
    city                VARCHAR(80)  NOT NULL DEFAULT '',
    address_line        VARCHAR(200) NOT NULL DEFAULT '',
    latitude            DOUBLE PRECISION,
    longitude           DOUBLE PRECISION,

    -- Why a reviewer rejected or suspended it. Shown to the applicant, so it is
    -- written for them to read, not as an internal note.
    review_note         VARCHAR(400),
    -- The object the approval created (delivery.merchant.id today).
    provisioned_ref_id  UUID,

    submitted_at        TIMESTAMPTZ,
    reviewed_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT partner_account_kind_chk
        CHECK (kind IN ('RESTAURANT', 'DRIVER', 'COURIER')),
    CONSTRAINT partner_account_status_chk
        CHECK (status IN ('DRAFT', 'SUBMITTED', 'APPROVED', 'REJECTED', 'SUSPENDED')),
    -- An approved account must point at what it provisioned; nothing else may.
    CONSTRAINT partner_account_provisioned_chk
        CHECK ((status IN ('APPROVED', 'SUSPENDED')) = (provisioned_ref_id IS NOT NULL))
);

-- One application per person per kind. A rejected application is *edited and
-- resubmitted*, not replaced — so "your application" stays singular, and its
-- documents (and the reviewer's note) survive the fix.
CREATE UNIQUE INDEX partner_account_user_kind_idx
    ON partner.partner_account (user_id, kind);
-- The reviewer's queue: oldest submission first.
CREATE INDEX partner_account_status_idx
    ON partner.partner_account (status, submitted_at);

-- KYC documents. These are identity papers, so they are NOT public media: the
-- stored value is a private S3 object key under private/…, never a public URL,
-- and it is read back only through a short-lived presigned GET. Everything the
-- app uploads through /v1/media/presign lands under media/*, which the bucket
-- policy makes world-readable — an ID card must never go there.
CREATE TABLE partner.partner_document (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id   UUID        NOT NULL REFERENCES partner.partner_account (id) ON DELETE CASCADE,
    kind         VARCHAR(32) NOT NULL,
    object_key   TEXT        NOT NULL,
    content_type VARCHAR(80) NOT NULL DEFAULT '',
    uploaded_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT partner_document_kind_chk
        CHECK (kind IN ('ID_FRONT', 'ID_BACK', 'SELFIE', 'BUSINESS_LICENSE',
                        'TAX_CERTIFICATE', 'FOOD_PERMIT', 'BANK_DETAILS'))
);

-- One document per kind: re-uploading a blurry ID replaces it rather than
-- leaving a reviewer to guess which of two is current.
CREATE UNIQUE INDEX partner_document_account_kind_idx
    ON partner.partner_document (account_id, kind);

-- The catalog side of the seam. A merchant now has an owner — the partner whose
-- approval created it — which is what lets delivery authorise "edit my own
-- restaurant" without knowing anything about applications or KYC. Nullable: the
-- V8 seed (since deleted) had no owner, and neither will anything an operator
-- inserts by hand.
ALTER TABLE delivery.merchant ADD COLUMN owner_id UUID;
CREATE INDEX merchant_owner_idx ON delivery.merchant (owner_id);

-- `active` is the owner's own switch ("we're open"). A platform block needs its
-- own flag, because the two are answers to different questions: restoring a
-- suspended partner must not fling open a restaurant the owner had closed, and
-- suspending one must not look, to them, like they closed it themselves.
-- Browse requires both.
ALTER TABLE delivery.merchant ADD COLUMN suspended BOOLEAN NOT NULL DEFAULT false;
