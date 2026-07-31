-- Currency columns: CHAR(3) → VARCHAR(3).
--
-- V23 declared them CHAR(3), reasoning that a currency code is exactly three
-- characters. It is, but Postgres reports CHAR as `bpchar` and Hibernate's
-- schema validation compares JDBC type codes, so a plain `String` field —
-- which every other currency column in this schema is mapped from — refuses to
-- start against it. Every other table in this database (economy.listing,
-- delivery.customer_order) already uses VARCHAR(3); this makes payments match
-- rather than making the entities special.
--
-- Forward-only, because V23 is already applied in production and editing an
-- applied migration changes its checksum, which Flyway is right to refuse.
--
-- There is a real behavioural difference beyond the type name, and it is the
-- better reason to prefer VARCHAR: CHAR pads with spaces, so a value that
-- arrived as 'US' would read back as 'US ' and compare unequal to itself.

ALTER TABLE payments.account        ALTER COLUMN currency TYPE VARCHAR(3);
ALTER TABLE payments.ledger_entry   ALTER COLUMN currency TYPE VARCHAR(3);
ALTER TABLE payments.stripe_payment ALTER COLUMN currency TYPE VARCHAR(3);
ALTER TABLE payments.payout         ALTER COLUMN currency TYPE VARCHAR(3);
