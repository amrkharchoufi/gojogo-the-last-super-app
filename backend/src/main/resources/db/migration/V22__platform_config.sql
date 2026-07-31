-- Platform config registry (SPECS.md §14).
--
-- Every milestone so far has answered "what should this number be?" with a Java
-- constant or an env var, and both answers have the same problem: changing the
-- number is a deploy. The vision needs token prices, platform fees, stake
-- amounts and TTLs to move without one — "GoJoAdmin changes token prices without
-- changing the driver experience" — so product policy lives in a table, read
-- through a single ConfigApi, and infra-ish values (hostnames, credentials,
-- pool sizes) stay in the environment where they belong.
--
-- The split is worth stating because it decides where a new knob goes: if
-- getting it wrong is a *business* decision, it belongs here; if getting it
-- wrong means the process can't start, it belongs in application.yml.
--
-- **Effective-dating is the whole design.** A row is never updated in place —
-- a change inserts a new row with a later effective_from, so "what was the
-- delivery fee on the 3rd of March" is answerable from the table itself, which
-- is the question every payment dispute eventually turns into. Reads take the
-- newest row not in the future.
--
-- There is deliberately no write endpoint yet. Values are seeded here and
-- overridden by later migrations until GoJoAdmin exists to edit them — the same
-- posture the music catalog and partner review took, for the same reason: this
-- app has no admin surface, and inventing a half-guarded one is worse than
-- waiting for the console that will own it.

CREATE SCHEMA IF NOT EXISTS platform;

CREATE TABLE platform.config (
    -- Dotted, namespaced by the module that reads it: `payments.*`, `delivery.*`.
    -- Not an enum — a knob's name is data, and a new module must be able to add
    -- one without a migration to some central list.
    key             VARCHAR(80)  NOT NULL,
    -- Stringly-typed on purpose: one table holds money amounts, basis points,
    -- durations and flags, and ConfigApi parses on read against the default the
    -- caller supplies. A value that won't parse falls back to that default and
    -- logs, because a typo in a config row must not take the platform down.
    value           VARCHAR(400) NOT NULL,
    effective_from  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    -- Why the value is what it is. Read by whoever changes it next.
    note            VARCHAR(300) NOT NULL DEFAULT '',
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),

    PRIMARY KEY (key, effective_from)
);

-- The read: newest row for a key that has already taken effect.
CREATE INDEX config_effective_idx ON platform.config (key, effective_from DESC);

-- Seeds. Defaults, not commitments (SPECS.md §1) — and every one of them is
-- also a compiled-in default at the call site, so an empty table behaves
-- identically. The rows exist so the values are *visible* and changeable, not
-- because anything depends on them being present.
INSERT INTO platform.config (key, value, note) VALUES
    -- Single currency until a second market exists (SPECS §15). Minor units
    -- everywhere; no module ever handles a decimal amount.
    ('platform.currency', 'USD', 'Single platform currency — multi-currency is deferred'),

    -- Wallet top-ups. The floor keeps Stripe's per-charge fee from exceeding
    -- the top-up; the ceiling is a fraud brake, not a product limit.
    ('payments.topup.min.minor', '500', 'Minimum card top-up: $5.00'),
    ('payments.topup.max.minor', '50000', 'Maximum single card top-up: $500.00'),
    ('payments.topup.session.ttl.minutes', '60', 'Stripe Checkout session lifetime'),

    -- Payouts out to a connected account.
    ('payments.payout.min.minor', '1000', 'Minimum payout: $10.00'),
    ('payments.payout.cooldown.hours', '24', 'Minimum gap between payouts for one payee'),

    -- Platform take on a delivery order, applied to the discounted food
    -- subtotal only — never to the delivery fee, the tip, or a promotion the
    -- merchant is already paying for. Mirrored in payments.fee_policy, which is
    -- the effective-dated source of truth; this row is what seeds it.
    ('delivery.platform.fee.bps', '1500', 'Platform commission on delivery food subtotal: 15%'),
    ('delivery.tip.max.minor', '10000', 'Largest tip accepted on one order: $100.00'),
    ('delivery.order.max.minor', '50000', 'Largest single order total: $500.00');
