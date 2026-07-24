-- Phase 2b · Milestone 4: delivery vertical (merchant catalog, orders, fulfilment).
-- user_id references profile.user_profile as a plain UUID — no foreign keys
-- across schemas, ever (ARCHITECTURE.md §3).

CREATE SCHEMA IF NOT EXISTS delivery;

CREATE TABLE delivery.merchant (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name               VARCHAR(120) NOT NULL,
    cuisine            VARCHAR(80)  NOT NULL,
    rating             NUMERIC(2,1) NOT NULL DEFAULT 4.5,
    review_count       INT          NOT NULL DEFAULT 0,
    eta_minutes        INT          NOT NULL DEFAULT 25,
    delivery_fee_cents INT          NOT NULL DEFAULT 0,
    image_url          TEXT,
    promo              VARCHAR(60),
    latitude           DOUBLE PRECISION NOT NULL DEFAULT 33.5731,
    longitude          DOUBLE PRECISION NOT NULL DEFAULT -7.5898,
    active             BOOLEAN      NOT NULL DEFAULT true,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX merchant_active_eta_idx ON delivery.merchant (active, eta_minutes);

-- Filterable browse facets (the iOS category strip) and display-only chips.
CREATE TABLE delivery.merchant_category (
    merchant_id UUID        NOT NULL REFERENCES delivery.merchant (id) ON DELETE CASCADE,
    category    VARCHAR(40) NOT NULL,
    PRIMARY KEY (merchant_id, category)
);
CREATE INDEX merchant_category_idx ON delivery.merchant_category (category);

CREATE TABLE delivery.merchant_tag (
    merchant_id UUID        NOT NULL REFERENCES delivery.merchant (id) ON DELETE CASCADE,
    tag         VARCHAR(40) NOT NULL,
    PRIMARY KEY (merchant_id, tag)
);

CREATE TABLE delivery.menu_section (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID         NOT NULL REFERENCES delivery.merchant (id) ON DELETE CASCADE,
    name        VARCHAR(80)  NOT NULL,
    sort_order  INT          NOT NULL DEFAULT 0
);
CREATE INDEX menu_section_merchant_idx ON delivery.menu_section (merchant_id, sort_order);

CREATE TABLE delivery.menu_item (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    section_id  UUID         NOT NULL REFERENCES delivery.menu_section (id) ON DELETE CASCADE,
    name        VARCHAR(120) NOT NULL,
    detail      VARCHAR(240) NOT NULL DEFAULT '',
    price_cents INT          NOT NULL,
    image_url   TEXT,
    popular     BOOLEAN      NOT NULL DEFAULT false,
    available   BOOLEAN      NOT NULL DEFAULT true,
    sort_order  INT          NOT NULL DEFAULT 0
);
CREATE INDEX menu_item_section_idx ON delivery.menu_item (section_id, sort_order);

-- "order" is reserved in SQL; the entity is Order-shaped but the table isn't.
CREATE TABLE delivery.customer_order (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            UUID         NOT NULL,
    merchant_id        UUID         NOT NULL REFERENCES delivery.merchant (id),
    status             VARCHAR(32)  NOT NULL,
    subtotal_cents     INT          NOT NULL,
    delivery_fee_cents INT          NOT NULL,
    service_fee_cents  INT          NOT NULL,
    total_cents        INT          NOT NULL,
    currency           VARCHAR(3)   NOT NULL DEFAULT 'USD',
    address_label      VARCHAR(120) NOT NULL DEFAULT '',
    note               VARCHAR(280) NOT NULL DEFAULT '',
    courier_name       VARCHAR(80),
    courier_vehicle    VARCHAR(60),
    courier_rating     NUMERIC(3,2),
    courier_deliveries INT,
    rating             INT,
    placed_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    status_changed_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    eta_at             TIMESTAMPTZ  NOT NULL,
    closed_at          TIMESTAMPTZ,
    -- Optimistic lock: the fulfilment job is the only writer of `status`, but
    -- more than one backend instance runs it, so a transition is claimed rather
    -- than assumed (the loser skips and re-reads on its next tick).
    version            INT          NOT NULL DEFAULT 0
);
-- Active-order lookup (one per user) and the history list.
CREATE INDEX customer_order_user_idx   ON delivery.customer_order (user_id, placed_at DESC);
CREATE INDEX customer_order_status_idx ON delivery.customer_order (status, status_changed_at);

CREATE TABLE delivery.order_line (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id         UUID         NOT NULL REFERENCES delivery.customer_order (id) ON DELETE CASCADE,
    menu_item_id     UUID         NOT NULL,
    name             VARCHAR(120) NOT NULL,
    unit_price_cents INT          NOT NULL,
    qty              INT          NOT NULL,
    sort_order       INT          NOT NULL DEFAULT 0
);
CREATE INDEX order_line_order_idx ON delivery.order_line (order_id, sort_order);

-- ---------------------------------------------------------------------------
-- Seed catalog. There is no merchant-onboarding surface yet (that's `partner`
-- in a later phase), so the catalog ships as data — fixed UUIDs so a re-run or
-- a rebuilt database keeps the same menu item ids that clients may have cached.
-- ---------------------------------------------------------------------------

INSERT INTO delivery.merchant
    (id, name, cuisine, rating, review_count, eta_minutes, delivery_fee_cents, promo, latitude, longitude) VALUES
    ('d0000000-0000-4000-8000-000000000001', 'Atlas Burger Co.', 'Burgers · American', 4.7, 1280, 22, 149, 'Free delivery', 33.5895, -7.6031),
    ('d0000000-0000-4000-8000-000000000002', 'Forno Nero',       'Pizza · Italian',    4.8,  940, 28, 199, NULL,            33.5731, -7.5898),
    ('d0000000-0000-4000-8000-000000000003', 'Kaido Sushi',      'Sushi · Japanese',   4.9,  612, 34, 249, NULL,            33.5650, -7.6420),
    ('d0000000-0000-4000-8000-000000000004', 'El Tapeo',         'Tacos · Mexican',    4.6, 1533, 19,  99, '20% off',       33.5820, -7.6190),
    ('d0000000-0000-4000-8000-000000000005', 'Verde Bowl',       'Healthy · Bowls',    4.5,  428, 17,   0, NULL,            33.5770, -7.6335),
    ('d0000000-0000-4000-8000-000000000006', 'Maison Sucrée',    'Dessert · Coffee',   4.8,  756, 24, 149, NULL,            33.5940, -7.6100);

INSERT INTO delivery.merchant_category (merchant_id, category) VALUES
    ('d0000000-0000-4000-8000-000000000001', 'Burgers'),
    ('d0000000-0000-4000-8000-000000000002', 'Pizza'),
    ('d0000000-0000-4000-8000-000000000003', 'Sushi'),
    ('d0000000-0000-4000-8000-000000000004', 'Tacos'),
    ('d0000000-0000-4000-8000-000000000005', 'Healthy'),
    ('d0000000-0000-4000-8000-000000000006', 'Dessert'),
    ('d0000000-0000-4000-8000-000000000006', 'Coffee');

INSERT INTO delivery.merchant_tag (merchant_id, tag) VALUES
    ('d0000000-0000-4000-8000-000000000001', 'Halal'),
    ('d0000000-0000-4000-8000-000000000001', 'Late night'),
    ('d0000000-0000-4000-8000-000000000002', 'Wood fired'),
    ('d0000000-0000-4000-8000-000000000003', 'Omakase'),
    ('d0000000-0000-4000-8000-000000000004', 'Street food'),
    ('d0000000-0000-4000-8000-000000000005', 'Vegan'),
    ('d0000000-0000-4000-8000-000000000005', 'Gluten free'),
    ('d0000000-0000-4000-8000-000000000006', 'Bakery');

INSERT INTO delivery.menu_section (id, merchant_id, name, sort_order) VALUES
    ('d1000000-0000-4000-8000-000000000101', 'd0000000-0000-4000-8000-000000000001', 'Burgers',   0),
    ('d1000000-0000-4000-8000-000000000102', 'd0000000-0000-4000-8000-000000000001', 'Sides',     1),
    ('d1000000-0000-4000-8000-000000000201', 'd0000000-0000-4000-8000-000000000002', 'Pizzas',    0),
    ('d1000000-0000-4000-8000-000000000202', 'd0000000-0000-4000-8000-000000000002', 'Antipasti', 1),
    ('d1000000-0000-4000-8000-000000000301', 'd0000000-0000-4000-8000-000000000003', 'Nigiri',    0),
    ('d1000000-0000-4000-8000-000000000302', 'd0000000-0000-4000-8000-000000000003', 'Rolls',     1),
    ('d1000000-0000-4000-8000-000000000401', 'd0000000-0000-4000-8000-000000000004', 'Tacos',     0),
    ('d1000000-0000-4000-8000-000000000402', 'd0000000-0000-4000-8000-000000000004', 'Sides',     1),
    ('d1000000-0000-4000-8000-000000000501', 'd0000000-0000-4000-8000-000000000005', 'Bowls',     0),
    ('d1000000-0000-4000-8000-000000000502', 'd0000000-0000-4000-8000-000000000005', 'Juices',    1),
    ('d1000000-0000-4000-8000-000000000601', 'd0000000-0000-4000-8000-000000000006', 'Pastries',  0),
    ('d1000000-0000-4000-8000-000000000602', 'd0000000-0000-4000-8000-000000000006', 'Coffee',    1);

INSERT INTO delivery.menu_item (id, section_id, name, detail, price_cents, popular, sort_order) VALUES
    -- Atlas Burger Co.
    ('d2000000-0000-4000-8000-000000000101', 'd1000000-0000-4000-8000-000000000101', 'Atlas Classic',      'Beef patty, aged cheddar, house sauce', 890, true,  0),
    ('d2000000-0000-4000-8000-000000000102', 'd1000000-0000-4000-8000-000000000101', 'Double Smash',       'Two smashed patties, pickles, onion',  1190, true,  1),
    ('d2000000-0000-4000-8000-000000000103', 'd1000000-0000-4000-8000-000000000101', 'Spiced Chicken',     'Buttermilk chicken, harissa mayo',      990, false, 2),
    ('d2000000-0000-4000-8000-000000000104', 'd1000000-0000-4000-8000-000000000102', 'Rosemary Fries',     'Sea salt, rosemary, aioli',            390, true,  0),
    ('d2000000-0000-4000-8000-000000000105', 'd1000000-0000-4000-8000-000000000102', 'Onion Rings',        'Beer batter, smoked ketchup',          420, false, 1),
    -- Forno Nero
    ('d2000000-0000-4000-8000-000000000201', 'd1000000-0000-4000-8000-000000000201', 'Margherita',         'San Marzano, fior di latte, basil',    1090, true,  0),
    ('d2000000-0000-4000-8000-000000000202', 'd1000000-0000-4000-8000-000000000201', 'Diavola',            'Spicy salami, chilli honey',           1290, true,  1),
    ('d2000000-0000-4000-8000-000000000203', 'd1000000-0000-4000-8000-000000000201', 'Quattro Formaggi',   'Four cheeses, black pepper',           1390, false, 2),
    ('d2000000-0000-4000-8000-000000000204', 'd1000000-0000-4000-8000-000000000202', 'Burrata & Tomato',   'Cherry tomato, olive oil, basil',       890, false, 0),
    ('d2000000-0000-4000-8000-000000000205', 'd1000000-0000-4000-8000-000000000202', 'Garlic Focaccia',    'Rosemary, flaky salt',                  490, false, 1),
    -- Kaido Sushi
    ('d2000000-0000-4000-8000-000000000301', 'd1000000-0000-4000-8000-000000000301', 'Salmon Nigiri (4)',  'Norwegian salmon, wasabi',              940, true,  0),
    ('d2000000-0000-4000-8000-000000000302', 'd1000000-0000-4000-8000-000000000301', 'Tuna Nigiri (4)',    'Yellowfin, aged soy',                  1140, false, 1),
    ('d2000000-0000-4000-8000-000000000303', 'd1000000-0000-4000-8000-000000000302', 'Dragon Roll',        'Eel, avocado, tobiko',                 1590, true,  0),
    ('d2000000-0000-4000-8000-000000000304', 'd1000000-0000-4000-8000-000000000302', 'Spicy Tuna Roll',    'Tuna, chilli mayo, cucumber',          1290, false, 1),
    -- El Tapeo
    ('d2000000-0000-4000-8000-000000000401', 'd1000000-0000-4000-8000-000000000401', 'Al Pastor (3)',      'Pork, pineapple, coriander',            790, true,  0),
    ('d2000000-0000-4000-8000-000000000402', 'd1000000-0000-4000-8000-000000000401', 'Carne Asada (3)',    'Grilled beef, salsa verde',             890, true,  1),
    ('d2000000-0000-4000-8000-000000000403', 'd1000000-0000-4000-8000-000000000401', 'Cauliflower (3)',    'Roasted cauliflower, chipotle crema',   690, false, 2),
    ('d2000000-0000-4000-8000-000000000404', 'd1000000-0000-4000-8000-000000000402', 'Chips & Guac',       'Fresh guacamole, lime',                 520, false, 0),
    -- Verde Bowl
    ('d2000000-0000-4000-8000-000000000501', 'd1000000-0000-4000-8000-000000000501', 'Green Power Bowl',   'Quinoa, avocado, kale, tahini',        1140, true,  0),
    ('d2000000-0000-4000-8000-000000000502', 'd1000000-0000-4000-8000-000000000501', 'Chicken Protein Bowl','Grilled chicken, brown rice, edamame', 1290, false, 1),
    ('d2000000-0000-4000-8000-000000000503', 'd1000000-0000-4000-8000-000000000502', 'Cold-Pressed Green', 'Cucumber, apple, ginger, mint',         620, false, 0),
    -- Maison Sucrée
    ('d2000000-0000-4000-8000-000000000601', 'd1000000-0000-4000-8000-000000000601', 'Pain au Chocolat',   'Butter laminated, twice baked',         340, true,  0),
    ('d2000000-0000-4000-8000-000000000602', 'd1000000-0000-4000-8000-000000000601', 'Pistachio Croissant','Pistachio cream, rose petals',          450, true,  1),
    ('d2000000-0000-4000-8000-000000000603', 'd1000000-0000-4000-8000-000000000602', 'Flat White',         'Double ristretto, silky milk',          380, false, 0),
    ('d2000000-0000-4000-8000-000000000604', 'd1000000-0000-4000-8000-000000000602', 'Iced Spanish Latte', 'Condensed milk, espresso',              420, false, 1);
