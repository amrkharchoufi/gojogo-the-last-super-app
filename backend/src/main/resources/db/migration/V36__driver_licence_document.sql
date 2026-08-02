-- A driving licence is a document the platform actually holds.
--
-- The partner flow has asked drivers for a "licence photo" since Phase 3 M2 and
-- had nowhere to put it: the app's tile toggled a boolean and uploaded nothing,
-- so an application reached a reviewer with a checkbox where the licence should
-- have been. A checkbox that claims a photo was taken is worse than no photo,
-- because it looks like evidence.
--
-- It goes in `partner_document` — alongside the other papers about a *person or
-- a business*, and deliberately not in `vehicle_document`, which holds claims
-- about a car. A licence belongs to whoever holds it and stays theirs when they
-- sell the Yaris.
--
-- It is also not an identity document, which is why an IDV vendor being
-- configured does not make it go away: Sumsub matches a face to an ID and says
-- nothing whatever about whether that person may drive. Whether it is *required*
-- depends on the vehicle rather than the kind — a trottinette needs no licence —
-- and that rule lives in PartnerService, not here.
ALTER TABLE partner.partner_document
    DROP CONSTRAINT partner_document_kind_chk;

ALTER TABLE partner.partner_document
    ADD CONSTRAINT partner_document_kind_chk
        CHECK (kind IN ('ID_FRONT', 'ID_BACK', 'SELFIE', 'BUSINESS_LICENSE',
                        'TAX_CERTIFICATE', 'FOOD_PERMIT', 'BANK_DETAILS',
                        'DRIVER_LICENSE'));
