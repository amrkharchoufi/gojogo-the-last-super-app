-- Phase 5 · Milestone 4: search & discovery (SPECS §13). One document table
-- with a generated tsvector — Postgres full-text is the store; the search
-- module's API hides it, which is where an OpenSearch client would land the
-- day a domain exists (none does; see PROGRESS).

CREATE SCHEMA IF NOT EXISTS search;

CREATE TABLE search.document (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    kind       VARCHAR(24)  NOT NULL,
    ref_id     UUID         NOT NULL,
    title      TEXT         NOT NULL DEFAULT '',
    body       TEXT         NOT NULL DEFAULT '',
    category   VARCHAR(60)  NOT NULL DEFAULT '',
    owner_id   UUID,
    -- Engagement counts, folded in by the source at render time; the ranking
    -- multiplies relevance by log(1 + popularity).
    popularity BIGINT       NOT NULL DEFAULT 0,
    active     BOOLEAN      NOT NULL DEFAULT true,
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    tsv        TSVECTOR     GENERATED ALWAYS AS (
        to_tsvector('simple', coalesce(title, '') || ' ' || coalesce(body, '')
            || ' ' || coalesce(category, ''))
    ) STORED,
    UNIQUE (kind, ref_id)
);
CREATE INDEX search_document_tsv_idx      ON search.document USING GIN (tsv);
CREATE INDEX search_document_trending_idx ON search.document (kind, active, popularity DESC);
