-- What the platform takes on Phase 5's two verticals, which until now was
-- nothing at all.
--
-- `V23` seeded `fee_policy` with DELIVERY at 1500 bps and TRAVEL at an explicit
-- zero — and said, in its own comment, why the zero row exists: "so the zero is
-- a decision on the record rather than a missing policy read as zero by
-- accident." Phase 5 then added `FeeApi.ECONOMY` and `FeeApi.SERVICES`, and
-- both verticals ask for a commission — `ProductOrderPayments` twice, once at
-- settlement and once for a digital capture, and `BookingPayments` once. Neither
-- got a row.
--
-- `FeeApi`'s contract is that a vertical with no policy is charged nothing,
-- which is the right default (the alternative is silently taking money nobody
-- agreed to) and is exactly why this was invisible: every marketplace sale and
-- every service booking settled the full amount to the seller, the platform
-- earned nothing, and no test or log said a word. Found by running one $24.90
-- order through the client end to end and reading the seller's ledger.
--
-- 1500 bps on both, matching delivery. The base is the caller's decision and
-- stays as built: the discounted goods value for a product order — never
-- shipping or tax — and the agreed price for a booking.
--
-- Effective-dated, so this does not change what the orders that already settled
-- were worth. The one order placed before this migration keeps its zero.
--
-- `FeePolicySeedTests` now fails the build if a vertical is added to `FeeApi`
-- without a row here.

INSERT INTO payments.fee_policy (vertical, percent_bps, fixed_minor, note) VALUES
    ('ECONOMY',  1500, 0, 'Commission on the discounted goods value only — never shipping or tax'),
    ('SERVICES', 1500, 0, 'Commission on the agreed price of the booking');
