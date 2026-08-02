-- Phase 3 · Milestone 5, corrected: the second half of the reward columns.
--
-- V33 added `reward_paid_minor` and stopped there, but `PartnerAccount` maps a
-- pair — `recordRewardPaid` writes the running total *and* the timestamp, the
-- same shape `kyc_fee_minor`/`kyc_fee_paid_at` has had since V30. The mapping
-- for the missing half validated against nothing, so every task booting the
-- M5 image died on `Schema-validation: missing column [reward_paid_at]` before
-- Tomcat ever took a request.
--
-- Its own migration rather than a fix to V33, because V33 has already run:
-- editing an applied migration changes its checksum and Flyway would then
-- refuse to start for a *second* reason.
--
-- Nullable, and that is the value rather than an oversight: null means this
-- application has never paid a verification reward, which is true of every row
-- that exists today and stays true for a driver whose vehicles are all
-- verified without incident. `reward_paid_minor` defaults to 0 for the same
-- reason — the two agree on the same "nothing has happened yet".

ALTER TABLE partner.partner_account
    ADD COLUMN reward_paid_at TIMESTAMPTZ;
