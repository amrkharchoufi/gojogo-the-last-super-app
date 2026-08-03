-- A finished job gets its own terminal state. `complete()` used to close the
-- row with the state still ASSIGNED, which kept it in `currentAssignment`
-- forever: the driver's app re-read the completed trip on every dispatch poll
-- and replayed the completion — card, haptic and earnings — each time.

-- The constraint must admit COMPLETED before any row is rewritten to it;
-- with the old constraint still in place the backfill UPDATE below violates
-- job_state_chk on the first row it touches.
ALTER TABLE dispatch.job
    DROP CONSTRAINT job_state_chk;
ALTER TABLE dispatch.job
    ADD CONSTRAINT job_state_chk CHECK (state IN
        ('SEARCHING', 'ASSIGNED', 'COMPLETED', 'EXHAUSTED', 'CANCELLED'));

-- Rows completed under the old code are exactly the ones closed while still
-- ASSIGNED (cancel and exhaust both wrote their own states).
UPDATE dispatch.job
SET state = 'COMPLETED'
WHERE state = 'ASSIGNED'
  AND closed_at IS NOT NULL;
