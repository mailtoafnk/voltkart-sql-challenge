/*
Q11 (Bonus): For each customer, the longest run of consecutive calendar
months in which they placed at least one completed order.
Required output: customer_id, customer_name, longest_streak_months

Classic gaps-and-islands pattern:
  1. YEAR(order_date)*12 + MONTH(order_date) turns each active month into
     a single integer that increases by exactly 1 per consecutive month,
     correctly handling year boundaries (Dec -> Jan).
  2. ROW_NUMBER() numbers each customer's active months in order.
  3. month_num - row_number is constant for every month inside one
     unbroken run, and changes the moment there's a gap -- this labels
     each streak.
  4. COUNT(*) per label = streak length; MAX per customer = the answer.

Verified against real data: 2,000 customers all get a streak value
(range: 1 to 27 months). The dataset spans exactly 27 months
(Jan 2023 - Mar 2025), and the top customer's streak of 27 was confirmed
by checking they have a completed order in literally every single month
in that span -- the theoretical maximum, which lines up correctly.
*/

WITH customer_months AS (
    SELECT DISTINCT
        customer_id,
        YEAR(order_date) * 12 + MONTH(order_date) AS month_num
    FROM dbo.fact_orders
    WHERE order_status = 'Completed'
),
numbered AS (
    SELECT
        customer_id,
        month_num,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY month_num) AS rn
    FROM customer_months
),
streaks AS (
    SELECT
        customer_id,
        month_num - rn AS streak_group,
        COUNT(*) AS streak_length
    FROM numbered
    GROUP BY customer_id, month_num - rn
),
longest AS (
    SELECT
        customer_id,
        MAX(streak_length) AS longest_streak_months
    FROM streaks
    GROUP BY customer_id
)
SELECT
    c.customer_id,
    c.customer_name,
    l.longest_streak_months
FROM longest l
JOIN dbo.dim_customer c ON c.customer_id = l.customer_id
ORDER BY l.longest_streak_months DESC;
