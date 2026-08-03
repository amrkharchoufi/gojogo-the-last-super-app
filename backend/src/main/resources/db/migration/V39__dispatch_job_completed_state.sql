-- A finished job gets its own terminal state. `complete()` used to close the
-- row with the state still ASSIGNED, which kept it in `currentAssignment`
-- forever: the driver's app re-read the completed trip on every dispatch poll
-- and replayed the completion — card, haptic and earnings — each time.

-- Rows completed under the old code are exactly the ones closed while still
-- ASSIGNED (cancel and exhaust both wrote their own states).
UPDATE dispatch.job
SET state = 'COMPLETED'
WHERE state = 'ASSIGNED'
  AND closed_at IS NOT NULL;

ALTER TABLE dispatch.job
    DROP CONSTRAINT job_state_chk;
ALTER TABLE dispatch.job
    ADD CONSTRAINT job_state_chk CHECK (state IN
        ('SEARCHING', 'ASSIGNED', 'COMPLETED', 'EXHAUSTED', 'CANCELLED'));
