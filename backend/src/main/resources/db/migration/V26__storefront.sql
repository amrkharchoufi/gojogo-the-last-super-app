-- Storefronts and profile home pages (SPECS.md §9, ARCHITECTURE.md Phase 2e M4).
--
-- Every commerce surface built so far renders a business the way this codebase
-- decided to render it: a hero image, then the menu. The vision's Studio lets a
-- business arrange its own page — a banner, a featured rail, a collection, an
-- offer, its own words — and this table is where that arrangement lives.
--
-- **One table for every surface, not a column per vertical.** A restaurant page,
-- a shop page and a brand's home page are the same document with different
-- blocks allowed on it, so `surface` is half the key and the platform module
-- validates the rest. A `storefront_json` column on delivery.merchant would have
-- been fewer files today and three divergent renderers by Phase 5.
--
-- **The blocks are a closed set, validated on write.** The column is text
-- holding a JSON array, not jsonb: nothing queries inside a document — it is
-- fetched whole by the one owner it belongs to and rendered — so jsonb would buy
-- only a binding this project cannot test locally. The shape guarantee comes
-- from the validator, which is stricter than "it parses" anyway.

CREATE SCHEMA IF NOT EXISTS storefront;

CREATE TABLE storefront.document (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),

    -- MERCHANT_STOREFRONT | BUSINESS_HOME. Not an enum type: a new surface
    -- arrives with a new vertical, and adding one should not be a migration
    -- that rewrites a type other tables depend on.
    surface     VARCHAR(32)  NOT NULL,
    -- Whose page. A merchant id for MERCHANT_STOREFRONT, a business profile id
    -- for BUSINESS_HOME — deliberately no FK, because the owner lives in a
    -- different module's schema and this module must not learn what a merchant
    -- is (the same posture payments takes toward its account owners).
    owner_id    UUID         NOT NULL,

    -- The author's counter: 1 on first save, +1 on each rewrite. 0 is
    -- unreachable here and means "never arranged" everywhere else, which is why
    -- an owner with no row and an owner with an empty page are different things.
    doc_version INT          NOT NULL DEFAULT 0,
    blocks      TEXT         NOT NULL DEFAULT '[]',

    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    -- JPA optimistic lock: two page builders saving at once is the case this
    -- module exists to serve, and the loser should be told rather than have
    -- their blocks silently win.
    row_version BIGINT       NOT NULL DEFAULT 0,

    CONSTRAINT document_version_chk CHECK (doc_version >= 0)
);

-- One page per owner per surface. The uniqueness is here rather than in the
-- primary key on purpose: an assigned composite id makes every JPA save a merge,
-- and "arrange for the first time" and "rewrite" stop being distinguishable.
CREATE UNIQUE INDEX document_owner_idx ON storefront.document (surface, owner_id);

-- Page-size knobs (SPECS §14). Both are also compiled-in defaults at the call
-- site, so an empty config table behaves identically; the rows exist so the
-- numbers are visible and changeable without a deploy.
INSERT INTO platform.config (key, value, note) VALUES
    ('storefront.max.blocks', '24',
     'Blocks per page — a scroll limit, not a technical one'),
    ('storefront.max.refs.per.block', '24',
     'Items in one rail, posts in one media row');
