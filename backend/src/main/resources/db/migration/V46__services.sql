-- Phase 5 · Milestone 3: the services vertical (SPECS §7) — provider profiles,
-- a bookable catalog, weekly availability, and the booking state machine.
-- Cross-schema references are plain UUIDs, never foreign keys.

CREATE SCHEMA IF NOT EXISTS services;

-- What a partner SERVICE_PROVIDER approval provisions
-- (services.ProviderProvisioningApi, the provisioning pattern's fourth
-- instance).
CREATE TABLE services.provider (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id  UUID         NOT NULL UNIQUE,
    display_name   VARCHAR(120) NOT NULL,
    logo_url       TEXT,
    bio            TEXT         NOT NULL DEFAULT '',
    -- The public half of qualifications: what a customer reads. The papers
    -- behind it are private documents below.
    qualifications TEXT         NOT NULL DEFAULT '',
    -- Regions served and languages spoken, as display strings the provider
    -- writes ("Casablanca, Rabat" / "Arabic, French, English") — filters can
    -- parse them later; the profile renders them today.
    service_areas  TEXT         NOT NULL DEFAULT '',
    languages      TEXT         NOT NULL DEFAULT '',
    -- The availability template reads in this zone — the lesson delivery's
    -- opening hours learned: a wall-clock rule without a zone is a lie twice
    -- a year.
    timezone       VARCHAR(50)  NOT NULL DEFAULT 'UTC',
    suspended      BOOLEAN      NOT NULL DEFAULT false,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Portfolio: public photos of past work.
CREATE TABLE services.provider_media (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id UUID NOT NULL REFERENCES services.provider (id) ON DELETE CASCADE,
    sort_order  INT  NOT NULL,
    image_url   TEXT NOT NULL
);
CREATE INDEX provider_media_provider_idx ON services.provider_media (provider_id);

-- Certification papers — private prefix object keys (MediaDocumentApi), read
-- through short-lived signed GETs. Never public URLs.
CREATE TABLE services.provider_document (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id UUID        NOT NULL REFERENCES services.provider (id) ON DELETE CASCADE,
    object_key  TEXT        NOT NULL,
    label       VARCHAR(80) NOT NULL DEFAULT '',
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX provider_document_provider_idx ON services.provider_document (provider_id);

-- The catalog. A null price is PRICE_ON_QUOTE: the number arrives in the
-- thread and lands on the booking, never back on the service.
CREATE TABLE services.service (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id      UUID         NOT NULL REFERENCES services.provider (id),
    name             VARCHAR(140) NOT NULL,
    description      TEXT         NOT NULL DEFAULT '',
    category         VARCHAR(60)  NOT NULL DEFAULT 'General',
    duration_minutes INT          NOT NULL,
    price_cents      BIGINT,
    location_kind    VARCHAR(16)  NOT NULL DEFAULT 'AT_PROVIDER',
    -- What the customer should know or prepare ("bring the vehicle papers").
    requirements     TEXT         NOT NULL DEFAULT '',
    active           BOOLEAN      NOT NULL DEFAULT true,
    hidden_at        TIMESTAMPTZ,
    rating_sum       BIGINT       NOT NULL DEFAULT 0,
    rating_count     INT          NOT NULL DEFAULT 0,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ
);
CREATE INDEX service_provider_idx ON services.service (provider_id, created_at DESC);
CREATE INDEX service_browse_idx   ON services.service (active, created_at DESC);
CREATE INDEX service_category_idx ON services.service (category);

-- The weekly template: open windows per weekday, minutes from midnight.
-- Bookable slots = template − exceptions − existing bookings − CONFIG buffer.
CREATE TABLE services.availability_rule (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id  UUID NOT NULL REFERENCES services.provider (id) ON DELETE CASCADE,
    day_of_week  INT  NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
    start_minute INT  NOT NULL CHECK (start_minute BETWEEN 0 AND 1439),
    end_minute   INT  NOT NULL CHECK (end_minute BETWEEN 1 AND 1440)
);
CREATE INDEX availability_rule_provider_idx ON services.availability_rule (provider_id);

-- Days the template doesn't apply — holidays, a closed week.
CREATE TABLE services.availability_exception (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id UUID NOT NULL REFERENCES services.provider (id) ON DELETE CASCADE,
    on_date     DATE NOT NULL,
    UNIQUE (provider_id, on_date)
);

-- The booking (SPECS §7): REQUESTED → CONFIRMED → COMPLETED | DECLINED |
-- CANCELLED_CUSTOMER | CANCELLED_PROVIDER | NO_SHOW. Money is held at request
-- for a priced service, at quote-acceptance for PRICE_ON_QUOTE.
CREATE TABLE services.booking (
    id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    service_id             UUID        NOT NULL,
    provider_id            UUID        NOT NULL,
    customer_id            UUID        NOT NULL,
    status                 VARCHAR(24) NOT NULL DEFAULT 'REQUESTED',
    starts_at              TIMESTAMPTZ NOT NULL,
    duration_minutes       INT         NOT NULL,
    -- Snapshot of the service price, or the accepted quote.
    price_cents            BIGINT,
    payment_status         VARCHAR(16) NOT NULL DEFAULT 'NONE',
    note                   TEXT        NOT NULL DEFAULT '',
    conversation_id        UUID,
    -- What a late cancellation or a no-show cost the customer.
    cancellation_fee_cents BIGINT      NOT NULL DEFAULT 0,
    requested_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    quoted_at              TIMESTAMPTZ,
    confirmed_at           TIMESTAMPTZ,
    completed_at           TIMESTAMPTZ,
    declined_at            TIMESTAMPTZ,
    cancelled_at           TIMESTAMPTZ,
    settled_at             TIMESTAMPTZ,
    reminded_24h           BOOLEAN     NOT NULL DEFAULT false,
    reminded_1h            BOOLEAN     NOT NULL DEFAULT false
);
CREATE INDEX booking_provider_time_idx ON services.booking (provider_id, starts_at);
CREATE INDEX booking_customer_idx     ON services.booking (customer_id, requested_at DESC);
CREATE INDEX booking_status_idx       ON services.booking (status, requested_at);
-- The settle sweep reads "completed and not yet paid out" directly.
CREATE INDEX booking_settle_idx ON services.booking (status, completed_at)
    WHERE status = 'COMPLETED';

-- Verified-booking reviews, the economy.review shape one vertical over.
CREATE TABLE services.review (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    service_id UUID        NOT NULL REFERENCES services.service (id) ON DELETE CASCADE,
    booking_id UUID        NOT NULL,
    author_id  UUID        NOT NULL,
    rating     INT         NOT NULL CHECK (rating BETWEEN 1 AND 5),
    body       TEXT        NOT NULL DEFAULT '',
    reply_body TEXT,
    replied_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE (service_id, author_id)
);
CREATE INDEX service_review_service_idx ON services.review (service_id, created_at DESC);
