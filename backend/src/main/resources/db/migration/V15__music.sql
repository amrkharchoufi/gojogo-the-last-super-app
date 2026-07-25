-- Music catalog — a platform module (ARCHITECTURE.md §2), not a story feature.
-- Stories are its first consumer; shorts and posts are the obvious next ones,
-- which is why the track lives here and not in `social`.
--
-- Ships EMPTY. Populating it is a licensing decision, not a code one — see
-- PROGRESS.md "Seeding the music catalog" for the INSERT. Deliberately no
-- ingest endpoint: this app has no admin role, and an unauthenticated writer
-- on the catalog would be a hole.

CREATE SCHEMA IF NOT EXISTS music;

CREATE TABLE music.track (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    title         TEXT        NOT NULL,
    artist        TEXT        NOT NULL,
    artwork_url   TEXT,
    audio_url     TEXT        NOT NULL,
    duration_ms   INT         NOT NULL,
    -- Editorial controls: pulling a track hides it from search without
    -- breaking the stories that already carry its snapshot.
    is_active     BOOLEAN     NOT NULL DEFAULT true,
    trending_rank INT,
    use_count     INT         NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE music.track
    ADD CONSTRAINT track_duration_chk CHECK (duration_ms > 0);

-- The default browse: hand-ranked first, then whatever people actually use.
CREATE INDEX track_trending_idx ON music.track (trending_rank, use_count DESC)
    WHERE is_active;

-- Search is a case-insensitive prefix/substring match over both fields; at
-- catalog sizes this stays cheap. Swap for pg_trgm if it ever isn't.
CREATE INDEX track_title_idx  ON music.track (lower(title))  WHERE is_active;
CREATE INDEX track_artist_idx ON music.track (lower(artist)) WHERE is_active;
