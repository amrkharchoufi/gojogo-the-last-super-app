-- Phase 2b · Milestone 5: seller listing management.
--
-- A listing was write-once (create / delete). A seller now edits it, pauses it,
-- and marks it sold — so `active BOOLEAN` isn't enough: "paused" and "sold" are
-- both "not browsable" but mean opposite things to the seller.

-- 1. Lifecycle. ACTIVE = in browse; PAUSED = hidden, seller still owns it;
--    SOLD = gone, kept for the seller's history and for anyone who saved it.
ALTER TABLE economy.listing
    ADD COLUMN status     VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    ADD COLUMN view_count INT         NOT NULL DEFAULT 0,
    ADD COLUMN updated_at TIMESTAMPTZ;

ALTER TABLE economy.listing
    ADD CONSTRAINT listing_status_chk CHECK (status IN ('ACTIVE', 'PAUSED', 'SOLD'));

UPDATE economy.listing SET status = CASE WHEN active THEN 'ACTIVE' ELSE 'PAUSED' END;

-- Browse reads status now, not active.
CREATE INDEX listing_status_created_idx ON economy.listing (status, created_at DESC);

-- `active` is deliberately LEFT IN PLACE, unread by the new code. Dropping it
-- would break the tasks still serving traffic during a rolling deploy (their
-- entity maps the column). It keeps its NOT NULL DEFAULT true, so inserts from
-- either version succeed; drop it in a later migration once nothing maps it.
COMMENT ON COLUMN economy.listing.active IS
    'Superseded by status (V10). Retained for rolling-deploy compatibility.';
