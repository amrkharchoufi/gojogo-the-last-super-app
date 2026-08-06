-- The two Phase 5 partner kinds, which the database has been refusing since
-- they shipped.
--
-- `V19` wrote `CHECK (kind IN ('RESTAURANT', 'DRIVER', 'COURIER'))` when those
-- were the only three. Phase 5 added SELLER (M1) and SERVICE_PROVIDER (M3) to
-- `PartnerKind`, wired both through the one provisioning switch, and gave each
-- a vertical to land in — and never widened this constraint. So every attempt
-- to create either kind failed the insert and surfaced as a generic 409
-- "Conflicting data", which reads like a duplicate rather than what it is.
--
-- What that cost: no seller and no service provider could exist in production
-- at all, so the whole merchant catalog, the digital shelf, the transfer
-- workflow and the booking machine were unreachable — not because they were
-- unbuilt, but because nothing could ever be approved to use them.
--
-- Why nothing caught it. 544 unit tests never touch a database. `ModularityTests`
-- reads the module graph. The `schema-check` job migrates a real Postgres and
-- boots the app, which proves the schema *loads* — booting inserts no rows, and
-- an unexercised CHECK constraint is invisible to it. The deploy was green. It
-- was found the first time anybody tried to approve a seller, which is the
-- fourth time in this repo that a path nothing had ever executed turned out not
-- to be a working path.
--
-- `PartnerKindConstraintTest` now fails the build if a constant is added to the
-- enum without appearing here.

ALTER TABLE partner.partner_account DROP CONSTRAINT partner_account_kind_chk;

ALTER TABLE partner.partner_account
    ADD CONSTRAINT partner_account_kind_chk
        CHECK (kind IN ('RESTAURANT', 'DRIVER', 'COURIER', 'SELLER', 'SERVICE_PROVIDER'));
