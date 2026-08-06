-- Trending was a lifetime leaderboard, not a trend: `popularity DESC` with no
-- time term, over a column only ever written when a document was created or
-- edited. Nothing reindexed on a like, a save or a rating, and no job
-- recomputed anything — so posts and listings sat at the popularity they had
-- at creation, which is zero, and the rail collapsed to "newest first".
--
-- What replaces it is a decaying accumulator, sampled on a schedule:
--
--   trend_score := engagement_gained_since_last_sample
--                  + trend_score * 0.5 ^ (elapsed / half_life)
--
-- `sampled_popularity` is what the counter read at the last sample, so the
-- difference is the engagement earned in that window and nothing else.
-- `sampled_at` carries the real elapsed time, so a late, missed or
-- restarted cycle decays by the time that actually passed rather than by
-- the number of cycles that happened to run.
--
-- NULL `sampled_at` means never sampled. The first sample only establishes
-- the baseline and scores nothing: crediting a lifetime count as if it were
-- earned in one window would open with a spike of all-time winners, which is
-- the exact behaviour being removed.

ALTER TABLE search.document
    ADD COLUMN trend_score        DOUBLE PRECISION NOT NULL DEFAULT 0,
    ADD COLUMN sampled_popularity BIGINT           NOT NULL DEFAULT 0,
    ADD COLUMN sampled_at         TIMESTAMPTZ;

-- The rail's read path.
CREATE INDEX search_document_trend_idx
    ON search.document (kind, active, trend_score DESC, popularity DESC);

-- The job's claim order: never-sampled first, then oldest sample.
CREATE INDEX search_document_trend_sample_idx
    ON search.document (active, sampled_at NULLS FIRST);
