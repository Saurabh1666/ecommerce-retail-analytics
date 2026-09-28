-- ============================================================
-- E-commerce Retail Analytics — Analysis Queries
-- Run against: data/ecommerce.db  (build it first with load_data.py)
-- Dialect: SQLite
-- Convention: "revenue" below always means Completed orders only,
-- unless a query is explicitly analysing Cancelled/Returned orders.
-- ============================================================


-- ------------------------------------------------------------
-- SECTION 1 — Foundational lookups & joins
-- ------------------------------------------------------------

-- 1.1 Completed orders in the last 90 days, with customer name and order value
SELECT
    o.order_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    o.order_date,
    o.payment_method,
    ROUND(SUM(oi.quantity * oi.unit_price), 2) AS order_value
FROM orders o
JOIN customers c   ON c.customer_id = o.customer_id
JOIN order_items oi ON oi.order_id  = o.order_id
WHERE o.status = 'Completed'
  AND o.order_date >= date('2026-09-14', '-90 days')
GROUP BY o.order_id
ORDER BY o.order_date DESC;

-- 1.2 Top 10 products by revenue
SELECT
    p.product_name,
    cat.category_name,
    SUM(oi.quantity)                              AS units_sold,
    ROUND(SUM(oi.quantity * oi.unit_price), 2)    AS revenue
FROM order_items oi
JOIN orders o      ON o.order_id = oi.order_id
JOIN products p    ON p.product_id = oi.product_id
JOIN categories cat ON cat.category_id = p.category_id
WHERE o.status = 'Completed'
GROUP BY p.product_id
ORDER BY revenue DESC
LIMIT 10;


-- ------------------------------------------------------------
-- SECTION 2 — Aggregation & grouping
-- ------------------------------------------------------------

-- 2.1 Revenue and margin % by category
SELECT
    cat.category_name,
    ROUND(SUM(oi.quantity * oi.unit_price), 2)                      AS revenue,
    ROUND(SUM(oi.quantity * p.unit_cost), 2)                        AS cost,
    ROUND(100.0 * (SUM(oi.quantity * oi.unit_price) - SUM(oi.quantity * p.unit_cost))
          / SUM(oi.quantity * oi.unit_price), 1)                    AS margin_pct
FROM order_items oi
JOIN orders o       ON o.order_id = oi.order_id
JOIN products p     ON p.product_id = oi.product_id
JOIN categories cat ON cat.category_id = p.category_id
WHERE o.status = 'Completed'
GROUP BY cat.category_id
ORDER BY revenue DESC;

-- 2.2 Average order value (AOV) by acquisition channel
SELECT
    c.acquisition_channel,
    COUNT(DISTINCT o.order_id)                         AS num_orders,
    ROUND(SUM(oi.quantity * oi.unit_price)
          / COUNT(DISTINCT o.order_id), 2)              AS avg_order_value
FROM orders o
JOIN customers c    ON c.customer_id = o.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status = 'Completed'
GROUP BY c.acquisition_channel
ORDER BY avg_order_value DESC;

-- 2.3 Cancellation / return rate by payment method
SELECT
    payment_method,
    COUNT(*)                                                       AS total_orders,
    SUM(CASE WHEN status = 'Cancelled' THEN 1 ELSE 0 END)          AS cancelled,
    SUM(CASE WHEN status = 'Returned' THEN 1 ELSE 0 END)           AS returned,
    ROUND(100.0 * SUM(CASE WHEN status IN ('Cancelled','Returned') THEN 1 ELSE 0 END)
          / COUNT(*), 1)                                            AS problem_rate_pct
FROM orders
GROUP BY payment_method
ORDER BY problem_rate_pct DESC;

-- 2.4 Lowest-rated products with a meaningful review count (5+ reviews) — candidates to investigate
SELECT
    p.product_name,
    COUNT(r.review_id)         AS num_reviews,
    ROUND(AVG(r.rating), 2)    AS avg_rating
FROM reviews r
JOIN products p ON p.product_id = r.product_id
GROUP BY p.product_id
HAVING COUNT(r.review_id) >= 5
ORDER BY avg_rating ASC
LIMIT 10;


-- ------------------------------------------------------------
-- SECTION 3 — CTEs: RFM segmentation & cohort retention
-- ------------------------------------------------------------

-- 3.1 RFM segmentation (Recency, Frequency, Monetary)
WITH order_summary AS (
    SELECT
        o.customer_id,
        MAX(o.order_date)                            AS last_order_date,
        COUNT(DISTINCT o.order_id)                    AS frequency,
        SUM(oi.quantity * oi.unit_price)              AS monetary
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status = 'Completed'
    GROUP BY o.customer_id
),
scored AS (
    SELECT
        customer_id,
        CAST(julianday('2026-09-14') - julianday(last_order_date) AS INTEGER) AS recency_days,
        frequency,
        ROUND(monetary, 2) AS monetary,
        NTILE(4) OVER (ORDER BY julianday(last_order_date) DESC) AS recency_score,
        NTILE(4) OVER (ORDER BY frequency ASC)                   AS frequency_score,
        NTILE(4) OVER (ORDER BY monetary ASC)                    AS monetary_score
    FROM order_summary
)
SELECT
    customer_id,
    recency_days,
    frequency,
    monetary,
    CASE
        WHEN recency_score >= 3 AND frequency_score >= 3 AND monetary_score >= 3 THEN 'Champions'
        WHEN recency_score >= 3 AND frequency_score < 3 THEN 'Promising / New'
        WHEN recency_score < 2 AND frequency_score >= 3 THEN 'At Risk (was loyal)'
        WHEN recency_score < 2 AND frequency_score < 2 THEN 'Lost'
        ELSE 'Regular'
    END AS rfm_segment
FROM scored
ORDER BY monetary DESC;

-- 3.2 Monthly cohort retention: % of each signup cohort still ordering N months later
WITH cohorts AS (
    SELECT customer_id, strftime('%Y-%m', signup_date) AS cohort_month
    FROM customers
),
order_months AS (
    SELECT DISTINCT customer_id, strftime('%Y-%m', order_date) AS order_month
    FROM orders
    WHERE status = 'Completed'
),
cohort_activity AS (
    SELECT
        c.cohort_month,
        om.order_month,
        (CAST(strftime('%Y', om.order_month || '-01') AS INTEGER) - CAST(strftime('%Y', c.cohort_month || '-01') AS INTEGER)) * 12
          + (CAST(strftime('%m', om.order_month || '-01') AS INTEGER) - CAST(strftime('%m', c.cohort_month || '-01') AS INTEGER)) AS months_since_signup,
        om.customer_id
    FROM cohorts c
    JOIN order_months om ON om.customer_id = c.customer_id
)
SELECT
    cohort_month,
    months_since_signup,
    COUNT(DISTINCT customer_id) AS active_customers
FROM cohort_activity
WHERE months_since_signup BETWEEN 0 AND 6
GROUP BY cohort_month, months_since_signup
ORDER BY cohort_month, months_since_signup;

-- 3.3 Churn candidates: customers with a completed order history but none in the last 180 days
WITH last_order AS (
    SELECT customer_id, MAX(order_date) AS last_order_date
    FROM orders
    WHERE status = 'Completed'
    GROUP BY customer_id
)
SELECT
    c.customer_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    lo.last_order_date,
    CAST(julianday('2026-09-14') - julianday(lo.last_order_date) AS INTEGER) AS days_since_last_order
FROM last_order lo
JOIN customers c ON c.customer_id = lo.customer_id
WHERE julianday('2026-09-14') - julianday(lo.last_order_date) > 180
ORDER BY days_since_last_order DESC;


-- ------------------------------------------------------------
-- SECTION 4 — Window functions
-- ------------------------------------------------------------

-- 4.1 Running total revenue over time
WITH daily AS (
    SELECT o.order_date, SUM(oi.quantity * oi.unit_price) AS daily_revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status = 'Completed'
    GROUP BY o.order_date
)
SELECT
    order_date,
    ROUND(daily_revenue, 2) AS daily_revenue,
    ROUND(SUM(daily_revenue) OVER (ORDER BY order_date), 2) AS cumulative_revenue
FROM daily
ORDER BY order_date;

-- 4.2 Rank products within their category by revenue
WITH product_revenue AS (
    SELECT
        p.product_id, p.product_name, cat.category_name,
        SUM(oi.quantity * oi.unit_price) AS revenue
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    JOIN categories cat ON cat.category_id = p.category_id
    WHERE o.status = 'Completed'
    GROUP BY p.product_id
)
SELECT
    category_name,
    product_name,
    ROUND(revenue, 2) AS revenue,
    RANK() OVER (PARTITION BY category_name ORDER BY revenue DESC) AS rank_in_category
FROM product_revenue
ORDER BY category_name, rank_in_category;

-- 4.3 Days between consecutive orders per customer (repeat-purchase interval)
WITH order_dates AS (
    SELECT DISTINCT customer_id, order_date
    FROM orders
    WHERE status = 'Completed'
)
SELECT
    customer_id,
    order_date,
    ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date) AS order_seq,
    julianday(order_date) - julianday(LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date)) AS days_since_prev_order
FROM order_dates
ORDER BY customer_id, order_date;

-- 4.4 New vs. repeat customer revenue split, by month
WITH order_seq AS (
    SELECT
        o.order_id, o.customer_id, o.order_date,
        SUM(oi.quantity * oi.unit_price) AS order_value,
        ROW_NUMBER() OVER (PARTITION BY o.customer_id ORDER BY o.order_date) AS seq
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status = 'Completed'
    GROUP BY o.order_id
)
SELECT
    strftime('%Y-%m', order_date) AS order_month,
    ROUND(SUM(CASE WHEN seq = 1 THEN order_value ELSE 0 END), 2) AS new_customer_revenue,
    ROUND(SUM(CASE WHEN seq > 1 THEN order_value ELSE 0 END), 2) AS repeat_customer_revenue
FROM order_seq
GROUP BY order_month
ORDER BY order_month;


-- ------------------------------------------------------------
-- SECTION 5 — Basket analysis (self-join)
-- ------------------------------------------------------------

-- 5.1 Top 10 product pairs most often bought together in the same order
SELECT
    p1.product_name AS product_a,
    p2.product_name AS product_b,
    COUNT(*) AS times_bought_together
FROM order_items oi1
JOIN order_items oi2 ON oi1.order_id = oi2.order_id AND oi1.product_id < oi2.product_id
JOIN products p1 ON p1.product_id = oi1.product_id
JOIN products p2 ON p2.product_id = oi2.product_id
GROUP BY oi1.product_id, oi2.product_id
ORDER BY times_bought_together DESC
LIMIT 10;
