-- Where a plate was issued, which is the thing that makes it unique.
--
-- The vehicle table has had a free-text `region` since Phase 3 M2, scoping the
-- "no two live vehicles share a plate" index, with a comment explaining that the
-- same string is a different car in another country. That was the right instinct
-- aimed at the wrong column: `region` holds a *city* somebody typed, and a city
-- is neither necessary nor sufficient for a plate's identity.
--
--   It misses duplicates. A Moroccan plate is issued nationally, so "12345-A-6
--   in Casablanca" and "12345-A-6 in Casa" are the same car — and the index let
--   both through, because the two strings differ.
--
--   It invents them across borders. Rabat is a city in Morocco and a city in
--   Malta; Tripoli is in Libya and in Lebanon; Valencia is in Spain and in
--   Venezuela. Two unrelated cars would collide on a name they happen to share.
--
-- Country fixes both, and keeping `region` in the key alongside it fixes the
-- third case: in the United States, Canada, Australia, India, Brazil, Mexico and
-- Nigeria plates really are issued by the state or province, and TEXAS ABC-1234
-- is not CALIFORNIA ABC-1234. So the app asks for a subdivision exactly where
-- one is part of the plate, leaves it empty everywhere else, and the index reads
-- the same either way.
ALTER TABLE partner.vehicle
    ADD COLUMN country VARCHAR(2) NOT NULL DEFAULT '';

-- Every vehicle written before this column existed was written by an app that
-- only ever asked about Morocco — its plate placeholder, its city placeholder
-- and its "carte grise" were all Moroccan. Backfilling to MA states what was
-- already true rather than leaving rows in a country of their own.
UPDATE partner.vehicle SET country = 'MA' WHERE country = '';

DROP INDEX partner.vehicle_plate_region_idx;

-- Retired vehicles stay excluded: selling a car and somebody else registering it
-- is the normal case, not fraud.
CREATE UNIQUE INDEX vehicle_plate_country_idx
    ON partner.vehicle (country, lower(region), lower(plate))
    WHERE state <> 'RETIRED' AND plate <> '';
