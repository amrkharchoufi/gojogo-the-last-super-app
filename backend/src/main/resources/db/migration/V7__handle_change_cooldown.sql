-- Username (handle) change policy: a user may change their handle a small number
-- of times for free (the onboarding pick + one grace change), after which a
-- 2-month cooldown applies between changes.
--   handle_changed_at  = when the handle was last changed (NULL = never by user)
--   handle_change_count = how many times the user has changed it (auto-generated
--                         signup handle does not count)
ALTER TABLE profile.user_profile
    ADD COLUMN handle_changed_at  TIMESTAMPTZ,
    ADD COLUMN handle_change_count INT NOT NULL DEFAULT 0;
