-- Payments + the GoJo Wallet (ARCHITECTURE.md §2b decision 2, SPECS.md §1).
--
-- Everything the platform will ever do with money — a delivery order, a
-- driver's $30 stake, ride-hailing tokens, a verification reward, a tip, a
-- refund, a payout — is a movement between two accounts. So there is one
-- double-entry ledger here and no per-vertical wallets: a vertical that kept
-- its own balances would eventually disagree with this one, and reconciling two
-- ledgers is a job nobody wants.
--
-- **Stripe is not the ledger.** External money in (a card top-up) and out (a
-- Connect payout) are the only things a vendor is needed for; both are mirrored
-- as ledger entries against an EXTERNAL account, which is what makes "how much
-- money entered the platform this month" a query rather than an export. Stripe
-- stays source of truth for the charge itself; the ledger reconciles against it.
--
-- **Balances are materialised, not summed.** A balance read happens on every
-- checkout, and summing an ever-growing entry table for it gets slower forever.
-- The account row carries the balance and the entry table carries the history;
-- the invariant that they agree is checked by LedgerAuditJob rather than
-- assumed. Every write takes the account row's optimistic lock, so two
-- concurrent debits cannot both read the same starting balance.

CREATE SCHEMA IF NOT EXISTS payments;

-- One row per (who, which pocket, which currency). Buckets are SPECS §1's:
--   AVAILABLE  spendable now
--   ESCROW     held for an order/booking in flight — the payer still owns it
--   STAKING    locked (Phase 3: the driver stake that funds verification)
--   TOKENS     ride-hailing tokens, a ledger credit with a policy price
--   REWARDS    earned, not bought (Phase 3 community verification)
--   EXTERNAL   the world outside GojoGo, on the far side of Stripe
CREATE TABLE payments.account (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),

    -- USER and MERCHANT ids are plain UUIDs from other schemas — no foreign
    -- keys across schemas, ever (ARCHITECTURE.md §4). PLATFORM and EXTERNAL are
    -- singletons and use the nil UUID, so the uniqueness index below covers
    -- them without a special case.
    owner_kind    VARCHAR(16)  NOT NULL,
    owner_id      UUID         NOT NULL,
    bucket        VARCHAR(16)  NOT NULL,
    currency      CHAR(3)      NOT NULL,

    balance_minor BIGINT       NOT NULL DEFAULT 0,
    -- The EXTERNAL account goes as negative as the platform has taken money in:
    -- it is the counterparty for every top-up, and money arriving from outside
    -- has to come from somewhere for the entries to balance. Everyone else is
    -- floored at zero — a user wallet that can go negative is a credit product,
    -- which this is not.
    allow_negative BOOLEAN     NOT NULL DEFAULT false,
    version       BIGINT       NOT NULL DEFAULT 0,

    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT account_owner_kind_chk
        CHECK (owner_kind IN ('USER', 'MERCHANT', 'PLATFORM', 'EXTERNAL')),
    CONSTRAINT account_bucket_chk
        CHECK (bucket IN ('AVAILABLE', 'ESCROW', 'STAKING', 'TOKENS', 'REWARDS', 'EXTERNAL')),
    CONSTRAINT account_balance_chk
        CHECK (allow_negative OR balance_minor >= 0)
);

CREATE UNIQUE INDEX account_identity_idx
    ON payments.account (owner_kind, owner_id, bucket, currency);

-- Every movement of money, ever. Append-only: a correction is another entry,
-- never an edit, because an edited ledger cannot be audited.
--
-- Convention, stated once so no reader has to guess: money leaves
-- `debit_account_id` and lands in `credit_account_id`. Both sides are always
-- present — there is no single-sided entry, which is what makes the sum of all
-- balances a constant and a missing counterparty impossible to express.
CREATE TABLE payments.ledger_entry (
    id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),

    -- The caller's key, and the reason a retried checkout cannot charge twice.
    -- It is a UNIQUE column rather than a lookup-then-insert because only the
    -- database can make that check atomic under concurrency: the second writer
    -- loses the insert, and the operation reports the first one's result.
    idempotency_key   VARCHAR(120) NOT NULL,

    debit_account_id  UUID         NOT NULL REFERENCES payments.account (id),
    credit_account_id UUID         NOT NULL REFERENCES payments.account (id),
    amount_minor      BIGINT       NOT NULL,
    currency          CHAR(3)      NOT NULL,

    -- What kind of movement this was, for statements and for the split a
    -- capture writes: an order capture is several entries that differ only in
    -- kind and payee (food to the merchant, commission to the platform, tip to
    -- the courier), and a receipt is just those entries read back.
    kind              VARCHAR(24)  NOT NULL,
    -- What it was about: ('ORDER', <order id>), ('TOPUP', <stripe payment id>),
    -- ('PAYOUT', <payout id>). Deliberately untyped and unconstrained — the
    -- ledger must be able to record a movement for a vertical it has never
    -- heard of, which is the point of it being a platform module.
    ref_kind          VARCHAR(24)  NOT NULL DEFAULT '',
    ref_id            UUID,
    -- One line a human can read on a statement. Never contains a card number,
    -- an address, or anything else that would make the ledger sensitive.
    memo              VARCHAR(200) NOT NULL DEFAULT '',

    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT ledger_amount_chk CHECK (amount_minor > 0),
    CONSTRAINT ledger_distinct_chk CHECK (debit_account_id <> credit_account_id),
    CONSTRAINT ledger_kind_chk CHECK (kind IN (
        'TOPUP', 'HOLD', 'RELEASE', 'CAPTURE', 'FEE', 'COURIER_FEE', 'TIP',
        'REFUND', 'PAYOUT', 'STAKE', 'STAKE_RELEASE', 'TOKEN_PURCHASE',
        'TOKEN_SPEND', 'REWARD', 'TRANSFER', 'ADJUSTMENT'))
);

CREATE UNIQUE INDEX ledger_idempotency_idx ON payments.ledger_entry (idempotency_key);
-- A statement is "everything that touched my account, newest first", and an
-- account appears on either side of an entry, so it needs both indexes.
CREATE INDEX ledger_debit_idx  ON payments.ledger_entry (debit_account_id, created_at DESC);
CREATE INDEX ledger_credit_idx ON payments.ledger_entry (credit_account_id, created_at DESC);
-- "Show me everything that happened to order X" — the receipt query, and what a
-- dispute is argued from.
CREATE INDEX ledger_ref_idx ON payments.ledger_entry (ref_kind, ref_id);

-- Money coming in from a card. One row per Stripe Checkout session we created,
-- mirroring its outcome — created here, completed by the webhook.
--
-- The wallet is credited from the *webhook*, never from the browser coming
-- back: a client returning to a success URL proves only that a browser visited
-- a URL. Stripe telling us, signed, is the event that moves money.
CREATE TABLE payments.stripe_payment (
    id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           UUID         NOT NULL,
    purpose           VARCHAR(16)  NOT NULL DEFAULT 'TOPUP',

    -- The Checkout session id (cs_…). Unique, so a replayed webhook finds the
    -- row it already completed instead of creating a second one.
    session_id        VARCHAR(120) NOT NULL,
    payment_intent_id VARCHAR(120),

    amount_minor      BIGINT       NOT NULL,
    currency          CHAR(3)      NOT NULL,
    status            VARCHAR(16)  NOT NULL DEFAULT 'CREATED',
    -- Where to send the customer. Not a secret — the session id in it is
    -- single-use and expires — but it is only useful to the person who asked.
    checkout_url      TEXT,
    -- The entry that credited the wallet, once one exists. Null while pending,
    -- which is also the flag that says "this session has not paid out yet".
    ledger_entry_id   UUID         REFERENCES payments.ledger_entry (id),

    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT stripe_payment_amount_chk CHECK (amount_minor > 0),
    CONSTRAINT stripe_payment_status_chk
        CHECK (status IN ('CREATED', 'SUCCEEDED', 'FAILED', 'EXPIRED'))
);

CREATE UNIQUE INDEX stripe_payment_session_idx ON payments.stripe_payment (session_id);
CREATE INDEX stripe_payment_user_idx ON payments.stripe_payment (user_id, created_at DESC);

-- Webhook idempotency, exactly the shape kyc.provider_event has and for the
-- same reason: Stripe retries anything non-2xx, and a replayed
-- checkout.session.completed must not credit a wallet twice. The insert is the
-- claim — the row existing is what says "already handled".
CREATE TABLE payments.provider_event (
    id           VARCHAR(80)  PRIMARY KEY,
    type         VARCHAR(64)  NOT NULL DEFAULT '',
    received_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX payments_provider_event_received_idx ON payments.provider_event (received_at);

-- What the platform takes, per vertical, effective-dated (SPECS §1).
-- Effective-dated rather than a config key because a fee change must not
-- retroactively change what an order that already settled was worth.
CREATE TABLE payments.fee_policy (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    vertical       VARCHAR(24)  NOT NULL,
    percent_bps    INT          NOT NULL DEFAULT 0,
    fixed_minor    INT          NOT NULL DEFAULT 0,
    effective_from TIMESTAMPTZ  NOT NULL DEFAULT now(),
    note           VARCHAR(300) NOT NULL DEFAULT '',
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT fee_policy_bps_chk CHECK (percent_bps BETWEEN 0 AND 10000),
    CONSTRAINT fee_policy_fixed_chk CHECK (fixed_minor >= 0)
);

CREATE UNIQUE INDEX fee_policy_effective_idx
    ON payments.fee_policy (vertical, effective_from);

INSERT INTO payments.fee_policy (vertical, percent_bps, fixed_minor, note) VALUES
    ('DELIVERY', 1500, 0, 'Commission on the discounted food subtotal only'),
    -- Rides are the token model: the platform sells tokens, so it takes no cut
    -- of the fare (SPECS §1). The row exists so the zero is a decision on the
    -- record rather than a missing policy read as zero by accident.
    ('TRAVEL',      0, 0, 'No commission — ride-hailing revenue is token packs');

-- A payee's Stripe Connect account: the only way money leaves the platform.
-- Attached at provisioning time for every payee kind (SPECS §1) — merchants
-- now, drivers and couriers in Phase 3/4, sellers and providers in Phase 5 —
-- which is why the owner is a (kind, id) pair rather than a merchant column.
CREATE TABLE payments.connect_account (
    id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_kind        VARCHAR(16)  NOT NULL,
    owner_id          UUID         NOT NULL,

    stripe_account_id VARCHAR(80)  NOT NULL,
    -- Stripe's two gates, mirrored so a payout can be refused with a reason
    -- instead of a failed transfer: the payee finished onboarding, and Stripe
    -- is willing to pay them.
    details_submitted BOOLEAN      NOT NULL DEFAULT false,
    payouts_enabled   BOOLEAN      NOT NULL DEFAULT false,
    -- Stripe's own words about what is still missing. Shown to the payee.
    requirements_note VARCHAR(400) NOT NULL DEFAULT '',

    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT connect_owner_kind_chk CHECK (owner_kind IN ('USER', 'MERCHANT'))
);

CREATE UNIQUE INDEX connect_account_owner_idx
    ON payments.connect_account (owner_kind, owner_id);
CREATE UNIQUE INDEX connect_account_stripe_idx
    ON payments.connect_account (stripe_account_id);

-- Money leaving for a connected account. The ledger entry is written first and
-- the transfer attempted second: a payout that debited nothing and paid out is
-- unrecoverable, whereas one that debited and failed to pay is a row that says
-- FAILED and a release entry.
CREATE TABLE payments.payout (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_kind         VARCHAR(16)  NOT NULL,
    owner_id           UUID         NOT NULL,
    -- Who asked, for the audit trail — a merchant payout is requested by its
    -- owner, and later by an operator in GoJoAdmin.
    requested_by       UUID,

    amount_minor       BIGINT       NOT NULL,
    currency           CHAR(3)      NOT NULL,
    status             VARCHAR(16)  NOT NULL DEFAULT 'REQUESTED',
    stripe_transfer_id VARCHAR(80),
    failure_reason     VARCHAR(300) NOT NULL DEFAULT '',
    ledger_entry_id    UUID         REFERENCES payments.ledger_entry (id),

    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT payout_amount_chk CHECK (amount_minor > 0),
    CONSTRAINT payout_status_chk CHECK (status IN ('REQUESTED', 'SENT', 'FAILED'))
);

CREATE INDEX payout_owner_idx ON payments.payout (owner_kind, owner_id, created_at DESC);
