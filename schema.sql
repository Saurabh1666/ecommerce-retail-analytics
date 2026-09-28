-- ============================================================
-- E-commerce Retail Analytics — Schema
-- Dialect: SQLite (portable; minor tweaks needed for Postgres/MySQL)
-- ============================================================

PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS reviews;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS categories;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id          INTEGER PRIMARY KEY,
    first_name           TEXT NOT NULL,
    last_name            TEXT NOT NULL,
    city                 TEXT NOT NULL,
    country              TEXT NOT NULL,
    signup_date          TEXT NOT NULL,
    acquisition_channel  TEXT NOT NULL CHECK (acquisition_channel IN ('Organic Search','Paid Social','Email','Referral','Direct'))
);

CREATE TABLE categories (
    category_id    INTEGER PRIMARY KEY,
    category_name  TEXT NOT NULL
);

CREATE TABLE products (
    product_id     INTEGER PRIMARY KEY,
    product_name   TEXT NOT NULL,
    category_id    INTEGER NOT NULL REFERENCES categories(category_id),
    unit_price     REAL NOT NULL,     -- current list price
    unit_cost      REAL NOT NULL      -- cost of goods, for margin analysis
);

CREATE TABLE orders (
    order_id       INTEGER PRIMARY KEY,
    customer_id    INTEGER NOT NULL REFERENCES customers(customer_id),
    order_date     TEXT NOT NULL,
    status         TEXT NOT NULL CHECK (status IN ('Completed','Cancelled','Returned')),
    payment_method TEXT NOT NULL CHECK (payment_method IN ('Card','PayPal','Bank Transfer','Gift Card'))
);

CREATE TABLE order_items (
    order_item_id  INTEGER PRIMARY KEY,
    order_id       INTEGER NOT NULL REFERENCES orders(order_id),
    product_id     INTEGER NOT NULL REFERENCES products(product_id),
    quantity       INTEGER NOT NULL,
    unit_price     REAL NOT NULL      -- price actually charged (may differ from products.unit_price)
);

CREATE TABLE reviews (
    review_id      INTEGER PRIMARY KEY,
    product_id     INTEGER NOT NULL REFERENCES products(product_id),
    customer_id    INTEGER NOT NULL REFERENCES customers(customer_id),
    rating         INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    review_date    TEXT NOT NULL
);

CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_date     ON orders(order_date);
CREATE INDEX idx_items_order     ON order_items(order_id);
CREATE INDEX idx_items_product   ON order_items(product_id);
CREATE INDEX idx_reviews_product ON reviews(product_id);
