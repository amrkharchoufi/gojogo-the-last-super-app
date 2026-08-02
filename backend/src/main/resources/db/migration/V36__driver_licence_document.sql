-- A driving licence is a document the platform actually holds.
--
-- The partner flow has asked drivers for a "licence photo" since Phase 3 M2 and
-- had nowhere to put it: the app's tile toggled a boolean and uploaded nothing,
-- so an application reached a reviewer with a checkbox where the licence should
-- have been. A checkbox that claims a photo was taken is worse than no photo,
-- because it looks like evidence.
--
-- The photos go in `partner_document` — alongside the other papers about a
-- *person or a business*, and deliberately not in `vehicle_document`, which
-- holds claims about a car. A licence belongs to whoever holds it and stays
-- theirs when they sell the Yaris.
--
-- They are also not identity documents, which is why an IDV vendor being
-- configured does not make them go away: Sumsub matches a face to an ID and says
-- nothing whatever about whether that person may drive. Whether they are
-- *required* depends on the vehicle rather than the kind — a trottinette needs
-- no licence — and that rule lives in PartnerService, not here.
--
-- Front and back are separate kinds rather than one "licence photo", because one
-- row holds one object: the back carries the categories a person is entitled to
-- drive and the expiry, and a reviewer who can only see the front is being asked
-- to approve half a document.
ALTER TABLE partner.partner_document
    DROP CONSTRAINT partner_document_kind_chk;

ALTER TABLE partner.partner_document
    ADD CONSTRAINT partner_document_kind_chk
        CHECK (kind IN ('ID_FRONT', 'ID_BACK', 'SELFIE', 'BUSINESS_LICENSE',
                        'TAX_CERTIFICATE', 'FOOD_PERMIT', 'BANK_DETAILS',
                        'DRIVER_LICENSE_FRONT', 'DRIVER_LICENSE_BACK'));

-- The number off the licence, which the form has collected since Phase 3 M2 and
-- then dropped on the floor — it lived in a local Swift struct, went into no
-- request, and reached no reviewer. Kept next to the contact details rather than
-- on the vehicle for the same reason the photos are: it is the driver's.
--
-- Nullable and unconstrained on purpose. Licence formats differ by country and
-- by decade, and a CHECK that encodes Morocco's would reject a Senegalese driver
-- with a perfectly valid one. What makes it trustworthy is the photo beside it
-- and the person who looks at both.
ALTER TABLE partner.partner_account
    ADD COLUMN driver_license_number VARCHAR(40) NOT NULL DEFAULT '';
